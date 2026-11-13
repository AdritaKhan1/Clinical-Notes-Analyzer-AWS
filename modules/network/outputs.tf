output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}

output "endpoints_security_group_id" {
  value = aws_security_group.endpoints.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "dynamodb_endpoint_id" {
  value = aws_vpc_endpoint.dynamodb.id
}
