resource "aws_eip" "gateway" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-gateway-eip" }
}

resource "aws_eip_association" "gateway" {
  instance_id   = aws_instance.gateway.id
  allocation_id = aws_eip.gateway.id
}

resource "aws_instance" "gateway" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gateway.id]
  key_name               = var.key_pair_name

  user_data = templatefile("${path.module}/../scripts/setup_gateway.sh", {
    engine_private_ip = aws_instance.engine.private_ip
  })

  tags = { Name = "${var.project_name}-gateway" }
}

resource "aws_instance" "engine" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.engine.id]
  key_name               = var.key_pair_name

  user_data = file("${path.module}/../scripts/setup_engine.sh")

  tags = { Name = "${var.project_name}-engine" }
}

resource "aws_instance" "math_worker" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]
  key_name               = var.key_pair_name

  user_data = templatefile("${path.module}/../scripts/setup_math_worker.sh", {
    engine_private_ip = aws_instance.engine.private_ip
  })

  tags       = { Name = "${var.project_name}-math-worker" }
  depends_on = [aws_instance.engine]
}

resource "aws_instance" "caller_worker" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]
  key_name               = var.key_pair_name

  user_data = templatefile("${path.module}/../scripts/setup_caller_worker.sh", {
    engine_private_ip = aws_instance.engine.private_ip
  })

  tags       = { Name = "${var.project_name}-caller-worker" }
  depends_on = [aws_instance.engine]
}
