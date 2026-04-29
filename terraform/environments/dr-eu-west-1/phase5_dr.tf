############################################################
# Phase 5 - DR routing handoff
#
# The DR compute layer now lives in phase3_compute.tf. After
# its Kubernetes public ingress creates the eu-west-1 ALB, feed
# that ALB DNS name and zone ID back into the primary env as
# dr_alb_dns_name/dr_alb_zone_id so Route 53 can publish the
# latency-based app records.
############################################################
