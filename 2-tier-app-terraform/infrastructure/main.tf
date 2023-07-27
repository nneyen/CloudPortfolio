/*Setup Network - VPC, Gateways, Subnets and Routetables*/

#Create the VPC
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs in eu-west-2"
  default     = ["eu-west-2a", "eu-west-2b"]
  type        = list(any)
}

variable "public_subnet_cidr" {
  default = ["10.0.0.0/24", "10.0.1.0/24"]
  type    = list(any)
}

variable "private_subnet_cidr" {
  default = ["10.0.2.0/24", "10.0.3.0/24"]
  type    = list(any)
}


resource "aws_vpc" "test_vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_hostnames = "true"
  tags = {
    Name = "test-vpc"
  }
}
#create internet gateway
resource "aws_internet_gateway" "test-igw" {
  vpc_id = aws_vpc.test_vpc.id
  tags = {
    Name = "test-igw"
  }
}

#create a public subnet in AZa and AZb
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidr)

  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = var.public_subnet_cidr[count.index]
  availability_zone = var.availability_zones[count.index]

}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidr)

  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = var.private_subnet_cidr[count.index]
  availability_zone = var.availability_zones[count.index]

}

#create a public route table
resource "aws_route_table" "pubrtb" {
  vpc_id = aws_vpc.test_vpc.id
  route {
    cidr_block = "0.0.0.0/0" #allow traffic from anywhere
    gateway_id = aws_internet_gateway.test-igw.id
  }
  tags = {
    Name = "test-pubrtb"
  }
}
#create route-table associations
resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidr)

  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.pubrtb.id
}

/* Create Security Groups */
#ssh security group to allow inbound ssh traffic
resource "aws_security_group" "public-sg" {
  name        = "public-sg"
  description = "Allows inbound traffic from public"
  vpc_id      = aws_vpc.test_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "testvpc-public-sg"
  }
}
#ALB Security group to allow traffic to application load balancer
resource "aws_security_group" "alb-sg" {
  name        = "alb-sg"
  description = "Allows traffic to application load balancer"
  vpc_id      = aws_vpc.test_vpc.id
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
  tags = {
    Name = "testvpc-alb-sg"
  }
}

#database security group to allow traffic to RDS
resource "aws_security_group" "db-sg" {
  name        = "db-sg"
  description = "Allows traffic to database-sg"
  vpc_id      = aws_vpc.test_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "testvpc-db-sg"
  }

}

/*Create Instances*/

#Create EC2 instances
resource "aws_instance" "webserver" {
  count                       = 2
  instance_type               = "t2.micro"
  key_name                    = "test-key"
  ami                         = "ami-0eb260c4d5475b901"
  vpc_security_group_ids      = [aws_security_group.public-sg.id]
  subnet_id                   = element(aws_subnet.public.*.id, count.index)
  user_data                   = file("scripts/install_apache")
  associate_public_ip_address = true

  tags = {
    Name = "webserver-${count.index + 1}"
  }
}

# Create DB Subnet Group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
  subnet_ids = aws_subnet.private[*].id
}

#Create DB Instance
resource "aws_db_instance" "db" {
  identifier             = "my-database"
  engine                 = "postgres"
  engine_version         = "14.6"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  multi_az               = false
  publicly_accessible    = true
  skip_final_snapshot    = true
  apply_immediately      = true
  username               = "myusername"
  password               = "mypassword"
  db_name                = "testdb"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db-sg.id]

  tags = {
    Name = "My Database"

  }
}

/*Load Balancers, Listeners and Target Groups */
#Create ALB
resource "aws_lb" "alb" {
  name               = "test-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = aws_subnet.public[*].id
}

#Create ALB Target Group
resource "aws_lb_target_group" "target_group" {
  name        = "mytargetgroup"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.test_vpc.id
  target_type = "instance"

  depends_on = [aws_vpc.test_vpc]
}
#target group attachments
resource "aws_lb_target_group_attachment" "tg_attachment" {
  count            = length(aws_instance.webserver)
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = aws_instance.webserver[count.index].id
  port             = 80
}

resource "aws_lb_listener" "alb_listener" {

  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}
