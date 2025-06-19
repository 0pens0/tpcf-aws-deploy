variable "tpcf_router_ips" {
  default = ["10.0.1.200", "10.0.1.201"]
}

variable "tpcf_mysql_proxy_ips" {
  default = ["10.0.1.210"]
}

variable "tpcf_diego_brain_ips" {
  default = ["10.0.1.220"]
}

resource "aws_security_group" "tpcf_router_sg" {
  name        = "tpcf-router-sg"
  description = "Allow HTTP/HTTPS traffic to Gorouter"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "tpcf_nlb" {
  name               = "tpcf-gorouter-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]
  tags = {
    Name = "tpcf-gorouter-nlb"
  }
}

resource "aws_lb_target_group" "tpcf_gorouter_tg" {
  name        = "tpcf-gorouter-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_lb_listener" "tpcf_https" {
  load_balancer_arn = aws_lb.tpcf_nlb.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = aws_acm_certificate_validation.opsman.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tpcf_gorouter_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "tpcf_gorouter_targets" {
  for_each = toset(var.tpcf_router_ips)

  target_group_arn = aws_lb_target_group.tpcf_gorouter_tg.arn
  target_id        = each.value
  port             = 80
}

resource "aws_route53_record" "apps_cf2" {
  zone_id = "Z01466373POHMJHH2K73L"
  name    = "*.apps.vmtanzu.com"
  type    = "A"

  alias {
    name                   = aws_lb.tpcf_nlb.dns_name
    zone_id                = aws_lb.tpcf_nlb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "sys_cf2" {
  zone_id = "Z01466373POHMJHH2K73L"
  name    = "*.sys.vmtanzu.com"
  type    = "A"

  alias {
    name                   = aws_lb.tpcf_nlb.dns_name
    zone_id                = aws_lb.tpcf_nlb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apps_wildcard" {
  zone_id = "Z01466373POHMJHH2K73L"
  name    = "*.apps.vmtanzu.net"
  type    = "A"

  alias {
    name                   = aws_lb.tpcf_nlb.dns_name
    zone_id                = aws_lb.tpcf_nlb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "sys_wildcard" {
  zone_id = "Z01466373POHMJHH2K73L"
  name    = "*.sys.vmtanzu.net"
  type    = "A"

  alias {
    name                   = aws_lb.tpcf_nlb.dns_name
    zone_id                = aws_lb.tpcf_nlb.zone_id
    evaluate_target_health = false
  }
}


output "tpcf_tile_static_ips" {
  value = jsonencode({
    router_static_ips      = var.tpcf_router_ips
    mysql_proxy_static_ips = var.tpcf_mysql_proxy_ips
    diego_brain_static_ips = var.tpcf_diego_brain_ips
    system_domain          = "sys.vmtanzu.com"
    apps_domain            = "apps.vmtanzu.com"
  })
}