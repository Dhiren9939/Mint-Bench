variable "region" {
  description = "The AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "Load generator size. Compute-optimised, no CPU credits, 4 vCPU / 8 GiB by default"
  type        = string
  default     = "c6i.xlarge"
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH to the load generator, e.g. your IP as 1.2.3.4/32"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ssh_public_key" {
  type        = string
  description = "The public key for the Mint key pair"
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0uYGtqbp73M9prIVb1nGl5aCXDqGiQ6cr4E3NIUifo1Mii0Tu/8EhOIqeShfLIc9RIflFru25/0h6P5z01pqjBFEKgtp1UbWkqT/xRXjf93b/M/P7SWjvMbQB+PcLW0i8JqBJO2er+mR5XOGMZa1V3yzbV/dUaE8nYES97RQFI+V10CehvoPHgBhte/zidUUqdrppd+lgSppzst3Wq7OQK1DXXYVD5myrzY2txNaj/dzAKaPIww4HV6xaWPnYfleXwHHqN0XjS56mmw5T4TWzlV+vS2ZQyIWLMaK1OhdDZTBioKQRhSxD87MpuYAxPhnNiWZqkhVbm2NsVL9V38pT MintKey"
}

variable "bench_table_arn" {
  description = "DynamoDB table the arm seeds from the load generator, null when the arm has none"
  type        = string
  default     = null
}

variable "bench_ecs_service_arn" {
  description = "ECS service the arm resets to its minimum task count before every pass, null when the arm has none"
  type        = string
  default     = null
}
