provider "aws" {
  region = "us-east-1"
  #access_key = 
  #secret_key = 
}

#1. Create vpc

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Production"
  }
}

#2. Create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

  tags = {
    Name = "prod-gateway"
  }
}

#3. Create custom route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod-route-table"
  }
}

#4. Create a subnet
resource "aws_subnet" "prod" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet1"
  }
}

#5. Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.prod.id
  route_table_id = aws_route_table.prod-route-table.id
}

#6. Create security group to allow port 22, 80 and 443
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}
#7. Create network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "webserver-nic" {
  subnet_id       = aws_subnet.prod.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_tls.id]
}
#8. Assign an elastic ip to the network created in step 7
# EIP require IGW to exist prior
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.webserver-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}


#9. create ubuntu server and install/enable apache2
resource "aws_instance" "webserver" {
  #ami                    = "ami-05fa00d4c63e32376" AWS Linux
  ami               = "ami-052efd3df9dad4825" #Ubuntu
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "enikey"
  #vpc_security_group_ids = ["sg-0fa8a3cfc63bb20e7"]
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.webserver-nic.id
  }
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y 
              sudo systemctl start apache2
              sudo bash -c 'echo Your first webserver to the world > /var/www/html/index.html'
              EOF
  #The name here appear on your AWS website
  tags = {
    Name    = "webserver"
    Project = "DevOps"
  }
}

output "server_private_ip" {
  value = aws_instance.webserver.private_ip
}
