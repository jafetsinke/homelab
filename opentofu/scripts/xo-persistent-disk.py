#!/usr/bin/env python3
"""Manage persistent XO VDIs outside xenorchestra_vm.disk via xo-cli."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time


class XOError(RuntimeError):
    pass


def log(message: str) -> None:
    print(message, flush=True)


def fail(message: str, code: int = 1) -> None:
    print(f"error: {message}", file=sys.stderr, flush=True)
    raise SystemExit(code)


def run_xo(args: list[str]) -> object:
    command = ["xo-cli", *args, "--json"]
    log(f"$ {' '.join(command)}")
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )
    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()
    if completed.returncode != 0:
        detail = stderr or stdout or f"exit code {completed.returncode}"
        fail(f"xo-cli failed: {detail}")
    if not stdout:
        return None
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        fail(f"xo-cli returned non-JSON output: {exc}: {stdout[:500]}")


def rest_get(path: str, *, fields: str | None = None, filter_expr: str | None = None) -> object:
    args = ["rest", "get", path]
    if fields is not None:
        args.append(f"fields={fields}")
    if filter_expr is not None:
        args.append(f"filter={filter_expr}")
    return run_xo(args)


def rest_list(collection: str, *, fields: str, filter_expr: str | None = None) -> list[dict]:
    args = ["rest", "get", collection, f"fields={fields}"]
    if filter_expr is not None:
        args.append(f"filter={filter_expr}")
    result = run_xo(args)
    if result is None:
        return []
    if not isinstance(result, list):
        fail(f"expected a list from {collection}, got {type(result).__name__}")
    return result


def normalize_sr_id(value: object) -> str:
    if not isinstance(value, str):
        fail(f"unexpected SR reference: {value!r}")
    if value.startswith("srs/"):
        return value.split("/", 1)[1]
    return value


def normalize_id(value: object) -> str:
    if not isinstance(value, str):
        fail(f"unexpected id value: {value!r}")
    if "/" in value:
        return value.split("/", 1)[1]
    return value


def vm_power_state(vm_id: str) -> str:
    vm = rest_get(f"vms/{vm_id}", fields="id,power_state")
    if not isinstance(vm, dict):
        fail(f"VM {vm_id} not found")
    state = vm.get("power_state")
    if not isinstance(state, str):
        fail(f"VM {vm_id} has no power_state")
    return state


def wait_vm_halted(vm_id: str, timeout_seconds: int = 600) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if vm_power_state(vm_id) == "Halted":
            return
        time.sleep(2)
    fail(f"timed out waiting for VM {vm_id} to halt")


def ensure_vm_halted(vm_id: str) -> None:
    state = vm_power_state(vm_id)
    if state == "Halted":
        return
    if state != "Running":
        fail(f"VM {vm_id} is in unsupported power state {state!r}; halt it before continuing")
    log(f"halting VM {vm_id} (clean shutdown)")
    run_xo(["vm.stop", f"id={vm_id}", "force=false"])
    wait_vm_halted(vm_id)


def find_vdis_by_name(vdi_name: str) -> list[dict]:
    escaped = vdi_name.replace('"', '\\"')
    return rest_list("vdis", fields="id,name_label,size,$SR,$VBDs", filter_expr=f'name_label:"{escaped}"')


def find_vdi(vdi_name: str, sr_id: str, size_bytes: int | None) -> dict:
    matches = [vdi for vdi in find_vdis_by_name(vdi_name) if normalize_sr_id(vdi.get("$SR")) == sr_id]
    if not matches:
        fail(f"VDI {vdi_name!r} not found on SR {sr_id}")
    if len(matches) > 1:
        ids = ", ".join(normalize_id(vdi.get("id")) for vdi in matches)
        fail(f"multiple VDIs named {vdi_name!r} on SR {sr_id}: {ids}")
    vdi = matches[0]
    if size_bytes is not None:
        ensure_vdi_size(vdi, size_bytes)
    return vdi


def ensure_vdi_size(vdi: dict, size_bytes: int) -> None:
    vdi_id = normalize_id(vdi.get("id"))
    current = vdi.get("size")
    if not isinstance(current, int):
        fail(f"VDI {vdi_id} has no size field")
    if current == size_bytes:
        return
    if current > size_bytes:
        fail(
            f"VDI {vdi_id} is {current} bytes but requested {size_bytes} bytes; "
            "refusing to shrink persistent data"
        )
    log(f"growing VDI {vdi_id} from {current} to {size_bytes} bytes")
    run_xo(["vdi.set", f"id={vdi_id}", f"size={size_bytes}"])


def create_vdi(vdi_name: str, sr_id: str, size_bytes: int) -> str:
    log(f"creating VDI {vdi_name!r} ({size_bytes} bytes) on SR {sr_id}")
    result = run_xo(
        [
            "disk.create",
            f"name={vdi_name}",
            f"size={size_bytes}",
            f"sr={sr_id}",
        ]
    )
    if isinstance(result, str):
        return result
    fail(f"unexpected disk.create result: {result!r}")


def vdi_attached_vm_ids(vdi: dict) -> list[str]:
    vbds = vdi.get("$VBDs")
    if not vbds:
        return []
    if not isinstance(vbds, list):
        fail(f"unexpected $VBDs field: {vbds!r}")
    vm_ids: list[str] = []
    for vbd_ref in vbds:
        vbd_id = normalize_id(vbd_ref)
        vbd = rest_get(f"vbds/{vbd_id}", fields="id,VM,VDI")
        if not isinstance(vbd, dict):
            continue
        vm_ref = vbd.get("VM")
        if vm_ref is None:
            continue
        vm_ids.append(normalize_id(vm_ref))
    return vm_ids


def find_vbd_for_vm_vdi(vm_id: str, vdi_id: str) -> dict | None:
    vm = rest_get(f"vms/{vm_id}", fields="id,$VBDs")
    if not isinstance(vm, dict):
        fail(f"VM {vm_id} not found")
    vbds = vm.get("$VBDs") or []
    if not isinstance(vbds, list):
        fail(f"unexpected $VBDs on VM {vm_id}")
    for vbd_ref in vbds:
        vbd_id = normalize_id(vbd_ref)
        vbd = rest_get(f"vbds/{vbd_id}", fields="id,VM,VDI,attached")
        if not isinstance(vbd, dict):
            continue
        if normalize_id(vbd.get("VDI")) != vdi_id:
            continue
        if normalize_id(vbd.get("VM")) != vm_id:
            continue
        return vbd
    return None


def attach_vdi(vm_id: str, vdi_id: str, position: str | None) -> None:
    args = ["vm.attachDisk", f"vm={vm_id}", f"vdi={vdi_id}", "bootable=false"]
    if position is not None:
        args.append(f"position={position}")
    run_xo(args)


def detach_vbd(vbd_id: str) -> None:
    vbd = rest_get(f"vbds/{vbd_id}", fields="id,attached")
    if not isinstance(vbd, dict):
        fail(f"VBD {vbd_id} not found")
    if vbd.get("attached"):
        log(f"disconnecting VBD {vbd_id}")
        run_xo(["vbd.disconnect", f"id={vbd_id}"])
    log(f"deleting VBD {vbd_id} (VDI is retained)")
    run_xo(["vbd.delete", f"id={vbd_id}"])


def cmd_ensure(args: argparse.Namespace) -> None:
    vm_id = args.vm_id
    ensure_vm_halted(vm_id)

    matches = [vdi for vdi in find_vdis_by_name(args.vdi_name) if normalize_sr_id(vdi.get("$SR")) == args.sr_id]
    if len(matches) > 1:
        ids = ", ".join(normalize_id(vdi.get("id")) for vdi in matches)
        fail(f"multiple VDIs named {args.vdi_name!r} on SR {args.sr_id}: {ids}")

    if matches:
        vdi = matches[0]
        ensure_vdi_size(vdi, args.size_bytes)
        vdi_id = normalize_id(vdi.get("id"))
    else:
        vdi_id = create_vdi(args.vdi_name, args.sr_id, args.size_bytes)
        vdi = rest_get(f"vdis/{vdi_id}", fields="id,name_label,size,$SR,$VBDs")

    attached_vms = vdi_attached_vm_ids(vdi)
    if vm_id in attached_vms:
        log(f"VDI {vdi_id} is already attached to VM {vm_id}")
        return

    if attached_vms:
        fail(
            f"VDI {vdi_id} is attached to unexpected VM(s): {', '.join(attached_vms)}; "
            f"refusing to attach to {vm_id}"
        )

    log(f"attaching VDI {vdi_id} to VM {vm_id}")
    attach_vdi(vm_id, vdi_id, args.position)
    log(f"attached VDI {vdi_id} to VM {vm_id}")


def cmd_detach(args: argparse.Namespace) -> None:
    vm_id = args.vm_id
    vdi = find_vdi(args.vdi_name, args.sr_id, None)
    vdi_id = normalize_id(vdi.get("id"))
    attached_vms = vdi_attached_vm_ids(vdi)

    if vm_id not in attached_vms:
        log(f"VDI {vdi_id} is not attached to VM {vm_id}; nothing to do")
        return

    if len(attached_vms) > 1:
        fail(f"VDI {vdi_id} is attached to multiple VMs: {', '.join(attached_vms)}")

    ensure_vm_halted(vm_id)
    vbd = find_vbd_for_vm_vdi(vm_id, vdi_id)
    if vbd is None:
        fail(f"VDI {vdi_id} appears attached to VM {vm_id} but no matching VBD was found")
    detach_vbd(normalize_id(vbd.get("id")))
    log(f"detached VDI {vdi_id} from VM {vm_id}")


def cmd_lookup(args: argparse.Namespace) -> None:
    vdi = find_vdi(args.vdi_name, args.sr_id, args.size_bytes)
    vdi_id = normalize_id(vdi.get("id"))
    print(vdi_id)


def cmd_lookup_external() -> None:
    try:
        query = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        fail(f"invalid external query JSON: {exc}")
    vdi_name = query.get("vdi_name")
    sr_id = query.get("sr_id")
    size_bytes = query.get("size_bytes")
    if not isinstance(vdi_name, str) or not isinstance(sr_id, str):
        fail("lookup-external requires vdi_name and sr_id strings")
    size = int(size_bytes) if size_bytes not in (None, "") else None
    vdi = find_vdi(vdi_name, sr_id, size)
    json.dump({"vdi_id": normalize_id(vdi.get("id"))}, sys.stdout)
    sys.stdout.write("\n")


def cmd_start_vm(args: argparse.Namespace) -> None:
    vm_id = args.vm_id
    state = vm_power_state(vm_id)
    if state == "Running":
        log(f"VM {vm_id} is already running")
        return
    if state != "Halted":
        fail(f"VM {vm_id} is in unsupported power state {state!r}; refusing to start")
    log(f"starting VM {vm_id}")
    run_xo(["vm.start", f"id={vm_id}"])
    deadline = time.time() + 300
    while time.time() < deadline:
        if vm_power_state(vm_id) == "Running":
            log(f"VM {vm_id} is running")
            return
        time.sleep(2)
    fail(f"timed out waiting for VM {vm_id} to start")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)

    ensure = subparsers.add_parser("ensure", help="find or create a VDI and attach it to a halted VM")
    ensure.add_argument("--vm-id", required=True)
    ensure.add_argument("--vdi-name", required=True)
    ensure.add_argument("--sr-id", required=True)
    ensure.add_argument("--size-bytes", type=int, required=True)
    ensure.add_argument("--position")

    detach = subparsers.add_parser("detach", help="detach a VDI from the expected VM without deleting it")
    detach.add_argument("--vm-id", required=True)
    detach.add_argument("--vdi-name", required=True)
    detach.add_argument("--sr-id", required=True)

    lookup = subparsers.add_parser("lookup", help="print a VDI UUID")
    lookup.add_argument("--vdi-name", required=True)
    lookup.add_argument("--sr-id", required=True)
    lookup.add_argument("--size-bytes", type=int)

    subparsers.add_parser("lookup-external", help=argparse.SUPPRESS)

    start_vm = subparsers.add_parser("start-vm", help="start a halted VM")
    start_vm.add_argument("--vm-id", required=True)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if args.action == "ensure":
        cmd_ensure(args)
    elif args.action == "detach":
        cmd_detach(args)
    elif args.action == "lookup":
        cmd_lookup(args)
    elif args.action == "lookup-external":
        cmd_lookup_external()
    elif args.action == "start-vm":
        cmd_start_vm(args)
    else:
        fail(f"unsupported action {args.action!r}")


if __name__ == "__main__":
    main()
