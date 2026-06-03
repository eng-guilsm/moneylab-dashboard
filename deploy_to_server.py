import os
import subprocess
import sys

# Connection details
ssh_key = r"keys\ssh-key-2026-06-02 (1).key"
ip = "136.248.80.104"
user = "ubuntu"
host = f"{user}@{ip}"
remote_dir = "/home/ubuntu/moneylab-dashboard"
repo_url = "https://github.com/eng-guilsm/moneylab-dashboard.git"

def run_ssh_command(cmd, desc):
    print(f"\n--- {desc} ---")
    ssh_cmd = [
        "ssh", "-i", ssh_key, 
        "-o", "StrictHostKeyChecking=no", 
        host, cmd
    ]
    res = subprocess.run(ssh_cmd, capture_output=True, text=True, errors="ignore")
    if res.returncode != 0:
        print(f"ERROR: {res.stderr.strip()}")
        return False
    print(res.stdout.strip())
    return True

def run_scp(local_path, remote_path, desc, is_dir=False):
    print(f"Uploading {desc}...")
    scp_cmd = [
        "scp", "-i", ssh_key, 
        "-o", "StrictHostKeyChecking=no"
    ]
    if is_dir:
        scp_cmd.append("-r")
    scp_cmd.extend([local_path, f"{host}:{remote_path}"])
    
    res = subprocess.run(scp_cmd, capture_output=True, text=True, errors="ignore")
    if res.returncode != 0:
        print(f"ERROR uploading {desc}: {res.stderr.strip()}")
        return False
    print(f"Successfully uploaded {desc}.")
    return True

def deploy():
    print("======================================================================")
    # Emojis removed to prevent encoding crash on windows terminal
    print("DEPLOYMENT TOOL: Implantando MoneyLab no Servidor Oracle Cloud")
    print("======================================================================")
    
    # 1. Clone repository on the server
    clone_cmd = f"sudo rm -rf {remote_dir} && git clone {repo_url} {remote_dir}"
    if not run_ssh_command(clone_cmd, "Clonando repositorio Git no servidor"):
        sys.exit(1)
        
    # 2. Upload config_auth.R (Confidential)
    if not run_scp("config_auth.R", f"{remote_dir}/config_auth.R", "config_auth.R"):
        sys.exit(1)
        
    # 3. Upload .secrets folder (Drive/Sheets auth tokens)
    if os.path.exists(".secrets"):
        if not run_scp(".secrets", f"{remote_dir}/.secrets", "pasta .secrets (autenticacao)", is_dir=True):
            sys.exit(1)
            
    # 4. Upload carteira.rds (Portfolio state)
    if os.path.exists("carteira.rds"):
        if not run_scp("carteira.rds", f"{remote_dir}/carteira.rds", "carteira.rds"):
            sys.exit(1)
            
    # 5. Upload optimized MoneyBot_Local.db (Database)
    if os.path.exists("MoneyBot_Local.db"):
        if not run_scp("MoneyBot_Local.db", f"{remote_dir}/MoneyBot_Local.db", "banco de dados SQLite"):
            sys.exit(1)
            
    # 6. Create Dockerfile on the server
    dockerfile_content = """FROM rocker/r-ver:4.3.2

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNING_IN_DOCKER=TRUE

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libsodium-dev \
    git \
    pandoc \
    make \
    cmake \
    gfortran \
    libnlopt-dev \
    zlib1g-dev \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . /app

RUN R -e "install.packages(c('quantmod', 'jsonlite', 'telegram.bot', 'lubridate', 'dplyr', 'tidyr', 'stringr', 'RSQLite', 'DBI', 'httr', 'httr2', 'PerformanceAnalytics', 'TTR', 'zoo', 'rugarch', 'nnet', 'rmarkdown', 'knitr', 'googlesheets4', 'googledrive', 'binancer', 'vars', 'ggplot2', 'scales', 'tidyRSS', 'digest', 'flexdashboard', 'dygraphs', 'xts'))"

CMD ["Rscript", "startLab.R"]
"""
    
    write_dockerfile_cmd = f"cat << 'EOF' > {remote_dir}/Dockerfile\n{dockerfile_content}\nEOF"
    if not run_ssh_command(write_dockerfile_cmd, "Criando Dockerfile no servidor"):
        sys.exit(1)
        
    # 7. Create docker-compose.yml on the server
    compose_content = """version: '3.8'

services:
  moneybot:
    build: .
    container_name: moneybot_core
    restart: always
    volumes:
      - .:/app
    environment:
      - TZ=America/Sao_Paulo
      - RUNNING_IN_DOCKER=TRUE

  moneydeploy:
    build: .
    container_name: moneybot_deploy
    restart: always
    volumes:
      - .:/app
    environment:
      - TZ=America/Sao_Paulo
      - RUNNING_IN_DOCKER=TRUE
    entrypoint: ["Rscript", "LabDeploy.R"]
"""
    
    write_compose_cmd = f"cat << 'EOF' > {remote_dir}/docker-compose.yml\n{compose_content}\nEOF"
    if not run_ssh_command(write_compose_cmd, "Criando docker-compose.yml no servidor"):
        sys.exit(1)
        
    # 8. Run Docker Compose build and startup
    startup_cmd = f"cd {remote_dir} && docker compose up -d --build"
    if not run_ssh_command(startup_cmd, "Iniciando contêineres Docker (moneybot_core e moneybot_deploy)"):
        sys.exit(1)
        
    # 9. Verify running containers
    run_ssh_command("docker ps", "Containers ativos no servidor")
    
    print("\n======================================================================")
    print("SUCCESS: MoneyLab implantado com sucesso no servidor e rodando 24/7!")
    print("======================================================================\n")

if __name__ == "__main__":
    deploy()
