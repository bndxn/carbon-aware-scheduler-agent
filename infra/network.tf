data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  name   = "default"
}

locals {
  sorted_subnet_ids = sort(data.aws_subnets.default.ids)
  # Express expects at least two subnets in different AZs; default VPCs usually satisfy this.
  subnet_ids = length(local.sorted_subnet_ids) >= 2 ? slice(local.sorted_subnet_ids, 0, 2) : local.sorted_subnet_ids
}
