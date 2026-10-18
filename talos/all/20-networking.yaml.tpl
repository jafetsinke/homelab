apiVersion: v1alpha1
kind: LinkConfig
name: enp1s0
addresses:
  - address: {{ .Node.IP }}/16
routes:
  - gateway: 10.53.0.1
---
apiVersion: v1alpha1
kind: ResolverConfig
nameservers:
  - address: 10.53.0.1
hostDNS:
  enabled: true
  forwardKubeDNSToHost: true
