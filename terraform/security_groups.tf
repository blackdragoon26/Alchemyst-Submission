# Gateway: accepts HTTP from the whole internet, SSH from anywhere
resource "aws_security_group" "gateway" {
  name   = "${var.project_name}-gateway-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-gateway-sg" }
}

# Engine: only reachable from inside the VPC — NOT from the internet
resource "aws_security_group" "engine" {
  name   = "${var.project_name}-engine-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Worker WebSocket RPC"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTP API (proxied from gateway)"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description     = "SSH from gateway only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-engine-sg" }
}

# Workers: SSH only from gateway, no inbound from internet
resource "aws_security_group" "workers" {
  name   = "${var.project_name}-workers-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "SSH from gateway only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-workers-sg" }
}
