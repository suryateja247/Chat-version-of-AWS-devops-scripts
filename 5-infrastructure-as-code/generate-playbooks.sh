#!/bin/bash

################################################################################
# Ansible Playbook Generator for Application Deployment
# Purpose: Generate reusable Ansible playbooks for multi-environment setup
# Usage: bash generate-playbooks.sh
################################################################################

echo "[INFO] Generating Ansible playbooks..."

# Create common variables file
cat > playbooks/group_vars/all.yml << 'EOF'
---
# Common variables for all environments

app_user: appuser
app_group: appgroup
app_home: /opt/app
app_port: 3000

# Docker configuration
docker_registry: "{{ aws_account_id }}.dkr.ecr.{{ aws_region }}.amazonaws.com"
docker_image_name: my-app
docker_image_tag: latest

# System updates
system_packages:
  - git
  - curl
  - wget
  - jq
  - awscli
  - docker.io
  - python3-pip

# CloudWatch Agent configuration
cloudwatch_config: /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
EOF

echo "[INFO] Created group_vars/all.yml"

# Create environment-specific variables
for ENV in dev staging prod; do
    cat > playbooks/group_vars/${ENV}.yml << EOF
---
# Environment-specific variables for $ENV

environment_name: $ENV

# Instance configuration
instance_type: t3.medium
volume_size: 50

# Application configuration
app_debug: false
log_level: INFO
EOF
    echo "[INFO] Created group_vars/${ENV}.yml"
done

# Create main playbook
cat > playbooks/deploy-app.yml << 'EOF'
---
- name: Deploy Application
  hosts: "{{ target_hosts | default('all') }}"
  become: yes
  become_user: root
  roles:
    - common
    - docker
    - application
  vars:
    ansible_python_interpreter: /usr/bin/python3
  tasks:
    - name: Display deployment info
      debug:
        msg: "Deploying {{ app_name }} to {{ environment_name }}"
EOF

echo "[INFO] Created deploy-app.yml"

# Create common role
mkdir -p playbooks/roles/common/tasks
cat > playbooks/roles/common/tasks/main.yml << 'EOF'
---
- name: Update system packages
  apt:
    update_cache: yes
    upgrade: dist
  when: ansible_os_family == "Debian"

- name: Install required packages
  package:
    name: "{{ system_packages }}"
    state: present

- name: Create application user
  user:
    name: "{{ app_user }}"
    group: "{{ app_group }}"
    home: "{{ app_home }}"
    shell: /bin/bash
    createhome: yes

- name: Set up CloudWatch agent
  shell: |
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s -c file:{{ cloudwatch_config }}
  ignore_errors: true
EOF

echo "[INFO] Created roles/common/tasks/main.yml"

# Create Docker role
mkdir -p playbooks/roles/docker/tasks
cat > playbooks/roles/docker/tasks/main.yml << 'EOF'
---
- name: Install Docker
  package:
    name: docker.io
    state: present

- name: Start Docker service
  systemd:
    name: docker
    state: started
    enabled: yes

- name: Add user to docker group
  user:
    name: "{{ app_user }}"
    groups: docker
    append: yes

- name: Log in to ECR
  shell: |
    aws ecr get-login-password --region {{ aws_region }} | \
    docker login --username AWS --password-stdin {{ docker_registry }}
  environment:
    AWS_DEFAULT_REGION: "{{ aws_region }}"
EOF

echo "[INFO] Created roles/docker/tasks/main.yml"

# Create application deployment role
mkdir -p playbooks/roles/application/tasks
cat > playbooks/roles/application/tasks/main.yml << 'EOF'
---
- name: Pull Docker image
  docker_image:
    name: "{{ docker_registry }}/{{ docker_image_name }}:{{ docker_image_tag }}"
    state: present

- name: Stop running container
  docker_container:
    name: "{{ app_name }}"
    state: stopped
  ignore_errors: true

- name: Remove old container
  docker_container:
    name: "{{ app_name }}"
    state: absent
  ignore_errors: true

- name: Start application container
  docker_container:
    name: "{{ app_name }}"
    image: "{{ docker_registry }}/{{ docker_image_name }}:{{ docker_image_tag }}"
    state: started
    restart_policy: always
    ports:
      - "{{ app_port }}:{{ app_port }}"
    env:
      ENVIRONMENT: "{{ environment_name }}"
      LOG_LEVEL: "{{ log_level }}"
      DEBUG: "{{ app_debug }}"
EOF

echo "[INFO] Created roles/application/tasks/main.yml"

# Create inventory file
cat > playbooks/hosts.ini << 'EOF'
[dev]
dev-app-01 ansible_host=10.0.10.10
dev-app-02 ansible_host=10.0.11.10

[staging]
staging-app-01 ansible_host=10.1.10.10
staging-app-02 ansible_host=10.1.11.10

[prod]
prod-app-01 ansible_host=10.2.10.10
prod-app-02 ansible_host=10.2.11.10
prod-app-03 ansible_host=10.2.10.20

[all:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=~/.ssh/id_rsa
EOF

echo "[INFO] Created hosts.ini"

echo "[SUCCESS] Ansible playbooks generated successfully!"
echo ""
echo "[INFO] To deploy using Ansible:"
echo "  ansible-playbook -i playbooks/hosts.ini playbooks/deploy-app.yml -e environment_name=dev"
echo ""
echo "[INFO] Playbook structure:"
echo "  playbooks/"
echo "  ├── deploy-app.yml"
echo "  ├── hosts.ini"
echo "  ├── group_vars/"
echo "  │   ├── all.yml"
echo "  │   ├── dev.yml"
echo "  │   ├── staging.yml"
echo "  │   └── prod.yml"
echo "  └── roles/"
echo "      ├── common/"
echo "      ├── docker/"
echo "      └── application/"

