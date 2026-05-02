############################################################
# Phase 5 - DR routing handoff
#
# The DR compute layer lives in phase3_compute.tf. The eu-west-1
# public ALB is created by applying k8s/overlays/eu-west-1 after
# the AWS Load Balancer Controller is installed. Feed that ALB DNS
# name and zone ID back into the primary env as dr_alb_dns_name and
# dr_alb_zone_id so Route 53 can publish the origin.<domain> latency
# records used by CloudFront, with ALB target-health evaluation.
############################################################
