
resource "aws_instance" "ubuntu_desktop" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = "m6i.xlarge"
  key_name               = "tpcf-key"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.desktop_sg.id]
  private_ip = "10.0.1.250" 
  root_block_device {
    volume_size = 500
    volume_type = "gp3"
  }

  tags = {
    Name = "UbuntuDesktop"
  }
}

resource "aws_security_group" "desktop_sg" {
  name   = "ubuntu-desktop-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5901
    to_port     = 5901
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