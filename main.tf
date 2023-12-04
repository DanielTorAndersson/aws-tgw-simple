provider "aws" {
  region = "eu-central-1"  # Change this to your desired AWS region
}


#######################################################
#######################################################
#Transit Gateway 
resource "aws_ec2_transit_gateway" "example" {
  description = "TGW-hub-spoke"
  
}

resource "aws_ec2_transit_gateway_vpc_attachment" "example" {
  subnet_ids         = [aws_subnet.hub_private_subnet.id, aws_subnet.hub_public_subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.example.id
  vpc_id             = aws_vpc.hub.id
  tags = {
    Name = "hub-attachment"
 }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "example1" {
  subnet_ids         = [aws_subnet.spoke_private_subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.example.id
  vpc_id             = aws_vpc.spoke.id
  tags = {
    Name = "spoke-attachment"
 }
} 


#######################################################
#######################################################
# Hub VPC
resource "aws_vpc" "hub" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "HubVPC"
  }
}

# Hub Internet Gateway
resource "aws_internet_gateway" "hub_igw" {
  vpc_id = aws_vpc.hub.id
  tags = {
    Name = "HubIGW"
  }
}

# Hub Public Subnet
resource "aws_subnet" "hub_public_subnet" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"  # Change this to your desired AZ
  map_public_ip_on_launch = true
  tags = {
    Name = "HubPublicSubnet"
  }
}

# Hub Private Subnet
resource "aws_subnet" "hub_private_subnet" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-central-1b"  # Change this to your desired AZ
  tags = {
    Name = "HubPrivateSubnet"
  }
}

# Create Hub Route Table
resource "aws_route_table" "hub_route_table" {
  depends_on = [aws_ec2_transit_gateway.example]
  vpc_id = aws_vpc.hub.id

  tags = {
    Name = "HubRouteTable"
  }
}

# Create a default route for the Internet Gateway
resource "aws_route" "hub_default_route" {
  route_table_id         = aws_route_table.hub_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.hub_igw.id
}

# Create a default route for the Internet Gateway
resource "aws_route" "hub_tgw_route" {
  route_table_id         = aws_route_table.hub_route_table.id
  destination_cidr_block = "10.1.0.0/16"
  gateway_id             = aws_ec2_transit_gateway.example.id
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "hub_public_association" {
  subnet_id      = aws_subnet.hub_public_subnet.id
  route_table_id = aws_route_table.hub_route_table.id
}

# Associate Route Table with Private Subnet
resource "aws_route_table_association" "hub_private_association" {
  subnet_id      = aws_subnet.hub_private_subnet.id
  route_table_id = aws_route_table.hub_route_table.id
}

#######################################################
#######################################################
# Spoke VPC
resource "aws_vpc" "spoke" {
  cidr_block = "10.1.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "SpokeVPC"
  }
}

# Spoke Private Subnet
resource "aws_subnet" "spoke_private_subnet" {
  vpc_id                  = aws_vpc.spoke.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "eu-central-1a"  # Change this to your desired AZ
  tags = {
    Name = "SpokePrivateSubnet"
  }
}

# Create Spoke Route Table
resource "aws_route_table" "spoke_route_table" {
  depends_on = [aws_ec2_transit_gateway.example]
  vpc_id = aws_vpc.spoke.id

  tags = {
    Name = "SpokeRouteTable"
  }
}

# Create a default route for the Internet Gateway
resource "aws_route" "spoke_default_route" {
  route_table_id         = aws_route_table.spoke_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_ec2_transit_gateway.example.id
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "spoke_public_association" {
  subnet_id      = aws_subnet.spoke_private_subnet.id
  route_table_id = aws_route_table.spoke_route_table.id
}


##################################################
##################################################
# EC2 Instance in Spoke Hub private subnet
resource "aws_instance" "nginx_instance1" {
  ami                    = "ami-0669b163befffbdfc"  # Amazon Linux 2 AMI, change as needed
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.hub_private_subnet.id
  key_name               = "my_key"  # Change this to your key pair
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum install -y nginx
              systemctl start nginx
              systemctl enable nginx
              EOF

  vpc_security_group_ids = [aws_security_group.allow_nginx1.id]  # Attach the security group directly

  tags = {
    Name = "NginxInstanceHub"
  }
}


# EC2 Instance in Spoke Private Subnet
resource "aws_instance" "nginx_instance" {
  ami                    = "ami-0669b163befffbdfc"  # Amazon Linux 2 AMI, change as needed
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.spoke_private_subnet.id
  key_name               = "my_key"  # Change this to your key pair

  user_data = <<-EOF
              #!/bin/bash
              yum install -y nginx
              systemctl start nginx
              systemctl enable nginx
              EOF

  vpc_security_group_ids = [aws_security_group.allow_nginx.id]  # Attach the security group directly

  tags = {
    Name = "NginxInstanceSpoke"
  }
}

# Security Group for Nginx Instance spoke
resource "aws_security_group" "allow_nginx1" {
  vpc_id = aws_vpc.hub.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all ingress ports from the internet"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all ICMP traffic from the internet"
  }

  tags = {
    Name = "hub-nginx"
  }
}

# Security Group for Nginx Instance spoke
resource "aws_security_group" "allow_nginx" {
  vpc_id = aws_vpc.spoke.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all ingress ports from the internet"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all ICMP traffic from the internet"
  }

  tags = {
    Name = "spoke-nginx"
  }
}
