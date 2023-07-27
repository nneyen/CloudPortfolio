# OVERVIEW

In this project, we will set up a simple 2-tier architecture using Terraform.
The aim of this project is to teach you how to show how to implement infrastructure as code. 
This is also an example of a highlighly available infrastructure.  
This Architecture will include the following:
- A VPC with public and private subnets
- An Internet gateway
- Security Groups
- RDS
- EC2 Instances 
- Application Load Balancer

This is my second time writing terraform, I tried a few things. 
- I loaded my user data from a file in the "scripts folder". I found that this made my code neater
- I utilized count to keep my resource blocks few - I must say this was both exciting and challenging. 

The next time I attempt this, I will try to use terraform modules

## Architecture
Here's a rough sketch of the Architecture

![2-Tier Architecture](media/architecture.jpg)

## Code Snippets

**Install Apache Script**
This is the user data script that is installed on the EC2 instance at launch
```
    #! /bin/bash
    sudo apt-get update
    sudo apt-get install -y apache2
    sudo systemctl start apache2
    sudo systemctl enable apache2
    echo "<h1> Hello! I was deployed via Terraform </h1>" | sudo tee /var/www/html/index.html

```

**Setting up VPC, Route Tables, Subnets, Security Groups and Internet Gateways**

The first thing I do when I set up my infrastructure in the cloud is to set up the network. That's VPCs, RouteTables, Subnets, Security Groups, Gateways. This is my foundation for all of my projects and I thoroughly enjoy this part. 

One thing I tried to do in this project was minimize resource blocks by using count and implicit referencing. It was a bit difficult to figure out but once I did, I was good to go. maybe next time, I would move the variables into their own file

```
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


    ```
    **Resource Scripts**

    Once the network is set up, its easy to provision resources. Here I will show you scripts for provisioning An EC2 instance and RDS instance- note that an RDS instance is not the actual DB, it is a database server and allows you to run several database engines. This took me a while to figure out. 🤦🏾‍♀️

    Also, RDS instances require a subnet group. 

    ```
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

```

**Load Balancing**
The final step of this project is to include load balancers. Load balancers help distribute incoming network traffic across multiple servers or resoources. It "balances" the load 😉

Loadbalancers require:
- Target groups
- Target attachments to your instances
- A listener on port 80 (HTTP) or/and port 443 ( HTTPS). Here its just port 80
```
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



```
**Running your terraform project**

Honestly, this thing works like magic 🪄 and once you start terraforming you will never go back 🤩

However here's one important thing to note - store your statefiles in an S3 bucket, that means you will have to create the bucket before you begin check `provider.tf` on how to do that

Run the following commands 
`terraform init` to download necessary libraries and modules.
`terraform plan` to show you a plan of your architecture. It shows you all the resources to be provisioned, etc. 
`terraform apply` to deploy code.

You should be able to see all your resources on AWS, especially the outputs of the DNS name to your load balancer:

![Load balancer DNS](media/dnsoutput.png)




and once you are ready, you can go ahead and destroy your resources with the command `terraform destroy`. This step is IMPORTANT so you do not incure charges. 


