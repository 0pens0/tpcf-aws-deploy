provider "aws" {
  region = "eu-west-2"
}

# Fetch latest Ubuntu 22.04 AMI via AWS SSM Parameter Store
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "tpcf-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-2a"
  tags = {
    Name = "tpcf-public-subnet"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-2b"
  tags = {
    Name = "tpcf-public-subnet-b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "assoc_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ssh" {
  name        = "tpcf-ssh"
  description = "Allow SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
  from_port   = 0
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"]
}

ingress {
  from_port   = 0
  to_port     = 65535
  protocol    = "udp"
  cidr_blocks = ["10.0.0.0/16"]
}

  ingress {
  from_port   = 6868
  to_port     = 6868
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"]
}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "opsman" {
  ami                    = "ami-0ed341313de8ff255"  # Tanzu Ops Manager AMI
  instance_type          = "m6i.xlarge"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id]
  key_name               = "tpcf-key"

  iam_instance_profile   = aws_iam_instance_profile.opsman_profile.name

  root_block_device {
    volume_size = 100    # Size in GB
    volume_type = "gp3"  # Or "gp2"
  }

  tags = {
    Name = "TPCF-OpsManager"
  }

    lifecycle {
    prevent_destroy = true
    ignore_changes = [
      ami,
      user_data,
      tags,
      vpc_security_group_ids,
    ]
  }
}

resource "aws_security_group_rule" "allow_https_in" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.ssh.id
  cidr_blocks       = ["0.0.0.0/0"]  # Or ALB SG only
}

resource "aws_acm_certificate" "opsman" {
  domain_name       = "opsman.vmtanzu.net"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.sys.vmtanzu.net",
    "*.apps.vmtanzu.net",
    "hub.vmtanzu.net"
  ]

  tags = {
    Name = "tanzu-acm-cert"
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.opsman.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = "Z01466373POHMJHH2K73L"  # Replace with your Route53 Zone ID
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "opsman" {
  certificate_arn         = aws_acm_certificate.opsman.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  depends_on = [
    aws_route53_record.cert_validation
  ]
}

resource "aws_lb" "opsman_alb" {
  name               = "opsman-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]
  security_groups    = [aws_security_group.ssh.id]

  tags = {
    Name = "opsman-alb"
  }
}

resource "aws_lb_target_group" "opsman_tg" {
  name     = "opsman-target-group"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/login"
    protocol            = "HTTPS"
    matcher             = "200-302"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "opsman_instance" {
  target_group_arn = aws_lb_target_group.opsman_tg.arn
  target_id        = aws_instance.opsman.id
  port             = 443
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.opsman_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.opsman.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.opsman_tg.arn
  }
}

resource "aws_route53_record" "opsman_alias" {
  zone_id = "Z01466373POHMJHH2K73L"  # <-- Replace this
  name    = "opsman.vmtanzu.net"
  type    = "A"

  alias {
    name                   = aws_lb.opsman_alb.dns_name
    zone_id                = aws_lb.opsman_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_iam_role" "opsman_role" {
  name = "tanzu-bosh-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "opsman_profile" {
  name = "tanzu-bosh-profile"
  role = aws_iam_role.opsman_role.name
}

resource "aws_iam_policy" "opsman_unified_policy" {
  name        = "opsman-unified-policy"
  description = "Unified IAM policy for Tanzu Ops Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        # General EC2
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeRegions",
        "ec2:DescribeInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVolumes",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:CreateVolume",
        "ec2:AttachVolume",
        "ec2:DeleteVolume",
        "ec2:CreateTags",

        # IAM / Profile
        "iam:GetInstanceProfile",
        "iam:PassRole",

        # Security Groups
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",

        # IAM profile association
        "ec2:AssociateIamInstanceProfile",
        "ec2:DescribeIamInstanceProfileAssociations",
        "ec2:DescribeAddresses",
        "ec2:ReplaceIamInstanceProfileAssociation",

        # Load Balancing
        "elasticloadbalancing:*"
      ],
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "opsman_policy_attachment" {
  role       = aws_iam_role.opsman_role.name
  policy_arn = aws_iam_policy.opsman_unified_policy.arn
}