# Cost model — what you'll actually pay

Real numbers from a production migration (Singapore region, May 2026). Adjust for your region using AWS pricing pages.

# As-built monthly cost (one production example)

```
Item                                              $/mo
=================================================== ====
ECS Fargate api (4 vCPU / 8 GB)                  180.00
VPC Endpoints (6 × 3 AZ)                         171.32
Aurora compute (Serverless v2, ~1 ACU avg)       116.80
ECS Fargate scheduler (2 vCPU / 4 GB)             89.97
NAT Gateway (compute + 30 GB)                     44.84
Aurora I/O (200k IO/hr sustained)                 32.12
ALB                                               24.24
Secrets Manager (8 grouped secrets)                3.20
CloudWatch Logs (5 GB ingest)                      2.65
CloudFront (2 distributions)                       1.00
Data Transfer Out                                  0.60
ECR storage                                        0.15
Aurora storage                                     0.04
S3                                                 0.01
=================================================== ====
TOTAL                                            667.00
ANNUAL                                          8004.00
```

# Right-sized monthly cost (same workload, optimized)

```
Item                                              $/mo
=================================================== ====
Aurora compute (settled to 0.5 ACU)               58.00
VPC Endpoints (6 × 1 AZ only)                     57.11
NAT Gateway                                       44.84
ECS Fargate api (0.5 vCPU / 1 GB)                 22.49
ALB                                               24.24
ECS Fargate scheduler (1 vCPU / 2 GB)             44.99
Aurora I/O                                        32.12
Secrets Manager                                    3.20
Everything else                                    4.41
=================================================== ====
TOTAL                                            291.40
ANNUAL                                          3496.80
```

# Comparison: Fly vs AWS

| Workload | Fly | AWS as-built | AWS right-sized |
|---|---|---|---|
| 2× perf-4x machines | $110 | n/a | n/a |
| Postgres dev cluster | $30 | n/a | n/a |
| 2× web shared-cpu-1x | $4 | n/a | n/a |
| 2× docs shared-cpu-1x | $4 | n/a | n/a |
| Anycast IPs | $2 | n/a | n/a |
| **Fly total** | **$150/mo** | | |
| ECS + Aurora + ALB + NAT + S3 + CloudFront | | **$667/mo** | **$291/mo** |
| **Cost multiplier vs Fly** | 1x | 4.4x | 1.9x |

# Why AWS costs more than Fly even right-sized

| Component | AWS adds | Fly equivalent |
|---|---|---|
| 🔴 NAT Gateway | $45/mo | Free (machines have public IP) |
| 🔴 ALB | $24/mo | Free (Fly's edge proxy) |
| 🔴 VPC Endpoints | $50-170/mo | Doesn't apply (no internal VPC) |
| 🟡 Aurora floor | $58/mo min | Fly Postgres dev = $30/mo |
| 🟢 Egress | $0.12/GB | $0.02/GB (cheaper on Fly) |
| 🟢 Cross-AZ data transfer | $0.01/GB | Free (single region) |

The **fixed overhead** of running on AWS is ~$120-200/mo for production-grade plumbing (NAT, ALB, endpoints). Fly bundles this into machine cost.

# Where the credits go

If you have AWS credits (typical $5K-$100K from startup programs):

| Credits | Months at as-built ($667) | Months at right-sized ($291) |
|---|---|---|
| $5,000 | 7.5 | 17 |
| $25,000 | 37 (3 years) | 86 (7 years) |
| $100,000 | 150 (12.5 years) | 343 (28 years) |

🟢 Even at as-built waste, credits make AWS effectively free for 3-12+ years for most projects.

# Component-by-component pricing (ap-southeast-1, 2026)

## Aurora Serverless v2
- $0.16/ACU-hour
- Standard storage: $0.12/GB-mo + $0.22/M IOs
- I/O-Optimized: +30% compute, free I/O (break-even at ~1M IO/hr)
- Backup: free up to AllocatedStorage size
- 🟡 **Performance Insights**: adds ~$0.02/vCPU-hour beyond the 7-day free retention window (~$14/mo on a 1 ACU cluster running 24/7 at longer retention). The Aurora template ships with it OFF by default (`var.aurora_performance_insights`); flip it on when you need query-level attribution.

## ECS Fargate
- $0.05056/vCPU-hour + $0.00553/GB-hour
- Spot: ~70% discount (interrupts every few hours; OK for batch, not for API)
- Savings Plans: 27% off with 1-year commitment

## VPC
- VPC itself: free
- NAT Gateway: $0.059/hr + $0.059/GB processed
- Interface VPC Endpoint: $0.013/hr/AZ + $0.01/GB processed
- Gateway VPC Endpoint (S3, DynamoDB): free
- Cross-AZ traffic: $0.01/GB each way

## ALB
- $0.0252/hr (idle baseline)
- $0.008/LCU-hour (active charges)
- Typical idle ALB: $22-26/mo

## CloudWatch
- Logs ingest: $0.50/GB
- Logs storage: $0.03/GB-mo
- Metrics: 10 custom metrics free, then $0.30/metric/mo
- Set retention to 30 days (default) or 7 days for non-critical logs

## Secrets Manager
- $0.40/secret/mo
- $0.05/10K API calls
- 🟢 **Optimization**: Group related secrets into one entry as JSON blob. 8 grouped entries = $3.20/mo vs 50 individual = $20/mo.

## S3
- Standard: $0.025/GB-mo storage
- Requests: $0.0053/1000 PUTs, $0.0004/1000 GETs
- Egress to CloudFront: free (private link)

## CloudFront
- PriceClass_100 (NA + EU only, cheapest): $0.085/GB first 10 TB
- HTTPS requests: $0.0120/10K
- Cache invalidations: 1000/mo free
- Cache hit ratio matters a lot — see Phase 7

## ECR
- Storage: $0.10/GB-mo (first 500 MB free)
- Cross-region transfer: $0.09/GB
- Same-region pull from ECS: free

## Data Transfer
- **OUT to internet:** $0.12/GB first 10 TB
- **Between AZs:** $0.01/GB each way
- **Same AZ:** free
- **From CloudFront to user:** counted as CloudFront egress (cheaper)

## Route 53
- Hosted zone: $0.50/mo
- Queries: $0.40/M
- Health checks: $0.50/check/mo
- 🟢 If using Cloudflare DNS: $0 (skip Route 53 entirely)

# Cost-cutting checklist for production AWS

🟢 Easy wins (per-month savings shown):

- [ ] Use ARM64 (Graviton) for ECS tasks → **-20% Fargate cost** (~$54 saved on $270 baseline)
- [ ] Group Secrets Manager entries → **-$16/mo** (40 → 8 secrets)
- [ ] Single-AZ VPC endpoints if only 1 task runs → **-$114/mo**
- [ ] Drop unnecessary VPC endpoints, use NAT instead → **-$170/mo** (adds ~$20 NAT)
- [ ] Right-size ECS task CPU/memory based on actual usage → **-$100-200/mo** typical
- [ ] CloudWatch Logs retention to 7 days for non-prod → **-50% logs cost**
- [ ] PriceClass_100 instead of PriceClass_All on CloudFront → **-30-50% CDN cost** (if you don't need global)
- [ ] Single CloudFront distribution with multiple aliases instead of one-per-site → minor

🟡 Medium effort:

- [ ] Spot Fargate for non-critical tasks (cron, scheduler) → **-70% Fargate cost**
- [ ] Fargate Compute Savings Plans (1 year, no upfront) → **-27% Fargate cost**
- [ ] Lambda for low-traffic API routes (split your monolith) → could be free
- [ ] CloudFront caching aggressive (Phase 7 in this skill) → **-50%+ origin requests**
- [ ] Use Cloudflare DNS + skip Route 53 → **-$0.50/mo per zone** (small but easy)

🔴 Big effort:

- [ ] Move to ap-south-1 (Mumbai) or us-east-1 (Virginia) for ~20% cheaper everything
- [ ] Self-hosted Postgres on EC2 instead of Aurora (if traffic is low) → could save $100+/mo
- [ ] Multi-tenant architecture to share Aurora across projects

# What you CAN'T cut

- 🔴 NAT Gateway: $43/mo minimum if you have private subnets that need internet
- 🔴 ALB: $22/mo minimum if you have an ALB
- 🔴 Aurora min ACU: $58/mo minimum (will change with 0-ACU auto-pause rollout)
- 🔴 ACM cert validation: free, but you need at least one Cloudflare DNS record

These are the AWS production-grade plumbing taxes. ~$120/mo regardless of traffic.

# When AWS becomes cheaper than Fly

AWS gets economically interesting when:

- Traffic is high enough that Fly's per-request pricing exceeds AWS's flat costs (~5M+ requests/month)
- You can use credits to neutralize the fixed plumbing tax
- You're already in the AWS ecosystem for other services (SES, S3 storage, Bedrock, etc.)
- You need features Fly lacks (RDS Proxy, EventBridge, Lambda, IAM granularity)

AWS stays expensive vs Fly when:

- Traffic is low-to-medium and credits aren't available
- You don't use multi-AZ HA
- You're a single-developer project that prefers Fly's UX

# How to track costs after migration

```bash
# Daily cost breakdown by service
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '7 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Set up a budget alarm at 80% of expected
aws budgets create-budget \
  --account-id $ACCOUNT \
  --budget '{
    "BudgetName": "monthly-aws-spend",
    "BudgetLimit": {"Amount": "300", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "you@example.com"
    }]
  }]'
```

🟡 Cost Explorer has 24-48h lag. Real-time cost monitoring requires AWS Cost & Usage Reports → Athena, which is heavier setup.
