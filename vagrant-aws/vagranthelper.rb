# -*- mode: ruby -*-
# vi: set ft=ruby :

def aws_instance(aws, override, ami, user, name, usePTY)
    # change these to your own specific keys or add them to your .profile or .bashrc file
    aws.access_key_id = ENV['AWS_ACCESS_KEY']
    aws.secret_access_key = ENV['AWS_SECRET_KEY']
    aws.keypair_name = ENV['AWS_KEYPAIR_NAME']

    # change these to reflect your preferences
    aws.region = "eu-west-1"
    aws.availability_zone = "eu-west-1a"
    aws.instance_type = "m3.medium"

    # change the security group to your default one or a custom one. Should have 22 and 9000 open
    aws.security_groups = "graylog2-security-group"
    aws.use_iam_profile = false

    aws.ami = ami

    override.ssh.pty=usePTY
    override.ssh.username = user

    # your aws .pem file
    override.ssh.private_key_path = ENV['AWS_PRIVATEKEY_PATH']

    aws.tags = {
      'Name' => name,
      'vagrant' => 'true'
    }
end
