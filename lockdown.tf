# Phase 3: endpoint policies on the free gateway endpoints.
#
# IAM decides what Lambda is allowed to do. These policies add a second,
# independent lock on the network path itself: even if a role were given
# too much access by mistake, traffic leaving this VPC could still only
# read clinical notes and write results, nothing else.

resource "aws_vpc_endpoint_policy" "s3" {
  vpc_endpoint_id = module.network.s3_endpoint_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ReadClinicalNotesOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${module.storage.incoming_bucket_arn}/notes/*"
    }]
  })
}

resource "aws_vpc_endpoint_policy" "dynamodb" {
  vpc_endpoint_id = module.network.dynamodb_endpoint_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "WriteResultsOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "dynamodb:PutItem"
      Resource  = module.storage.results_table_arn
    }]
  })
}
