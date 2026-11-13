# A VPC with private subnets only. There is no internet gateway and no
# NAT gateway, so nothing inside can reach the internet. AWS services are
# reached through VPC endpoints instead, which keeps traffic on AWS's network
# and avoids the ~$35/month a NAT gateway would cost.

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # needed later for interface endpoints

  tags = { Name = "${var.project_name}-vpc" }
}

# Two private subnets in different availability zones so Lambda can
# keep running if one zone has problems.
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.project_name}-private-${count.index + 1}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Gateway endpoints are free. They add routes so the subnets can reach
# S3 and DynamoDB privately.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project_name}-s3-endpoint" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project_name}-dynamodb-endpoint" }
}

# Security group the Lambda function will use in Phase 2.
# Outbound HTTPS only, and only to S3, DynamoDB, or inside the VPC
# (where the interface endpoints will live).
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-sg"
  description = "Lambda: outbound HTTPS to AWS services only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.project_name}-lambda-sg" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_s3" {
  security_group_id = aws_security_group.lambda.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_dynamodb" {
  security_group_id = aws_security_group.lambda.id
  prefix_list_id    = aws_vpc_endpoint.dynamodb.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_vpc" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Security group for the interface endpoints added in Phase 2.
# Only accepts HTTPS from the Lambda security group.
resource "aws_security_group" "endpoints" {
  name        = "${var.project_name}-endpoints-sg"
  description = "Interface endpoints: HTTPS from Lambda only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.project_name}-endpoints-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_lambda" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
