#!/usr/bin/env bash
# cert_renewal_modern.sh - A modernized script for Hail certificate renewal
# Improved with better organization, visual feedback, and spinners

# Exit on error, undefined vars, and propagate pipe failures
set -euo pipefail

# ===== UTILITY FUNCTIONS =====

# ANSI color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# Emoji
readonly CHECK="✅"
readonly CROSS="❌"
readonly ROCKET="🚀"
readonly WARNING="⚠️"
readonly DNA="🧬"
readonly CLOCK="🕒"
readonly CERT="🔒"
readonly SERVER="🖥️"
readonly MONEY="💰"

# Function to print styled messages
print_info() {
  printf "${BLUE}${BOLD}[INFO]${RESET} ${BLUE}%s${RESET}\n" "$1"
}

print_success() {
  printf "${GREEN}${BOLD}[SUCCESS]${RESET} ${GREEN}%s ${CHECK}${RESET}\n" "$1"
}

print_warning() {
  printf "${YELLOW}${BOLD}[WARNING]${RESET} ${YELLOW}%s ${WARNING}${RESET}\n" "$1"
}

print_error() {
  printf "${RED}${BOLD}[ERROR]${RESET} ${RED}%s ${CROSS}${RESET}\n" "$1"
}

# Spinner animation for long-running processes
spinner() {
  local pid=$1
  local delay=0.1
  local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local message=$2
  local success_msg=$3
  local error_msg=$4
  
  printf "${CYAN}${message}${RESET} "
  
  while kill -0 $pid 2>/dev/null; do
    local i
    for i in $(seq 0 9); do
      printf "\b${CYAN}${spin_chars:$i:1}${RESET}"
      sleep $delay
    done
  done
  
  wait $pid
  local status=$?
  printf "\b"
  
  if [ $status -eq 0 ]; then
    print_success "${success_msg}"
    return 0
  else
    print_error "${error_msg}"
    return 1
  fi
}

# Execute command with visual feedback
run_command() {
  local cmd=$1
  local msg=$2
  local success_msg=$3
  local error_msg=$4
  
  print_info "${msg} ${CLOCK}"
  eval $cmd &>/dev/null & 
  spinner $! "${msg}" "${success_msg}" "${error_msg}"
  return $?
}

# ASCII Art Banner in cool colors
print_banner() {
cat << 'EOF'

${BOLD}${PURPLE}██   ██  █████  ██ ██${RESET}      ${BOLD}${CYAN} ██████ ███████ ██████  ████████${RESET}
${BOLD}${PURPLE}██   ██ ██   ██ ██ ██${RESET}      ${BOLD}${CYAN}██      ██      ██   ██    ██   ${RESET}
${BOLD}${PURPLE}███████ ███████ ██ ██${RESET}      ${BOLD}${CYAN}██      █████   ██████     ██   ${RESET}
${BOLD}${PURPLE}██   ██ ██   ██ ██ ██${RESET}      ${BOLD}${CYAN}██      ██      ██   ██    ██   ${RESET}
${BOLD}${PURPLE}██   ██ ██   ██ ██ ███████${RESET} ${BOLD}${CYAN} ██████ ███████ ██   ██    ██   ${RESET}
                                                             
${BOLD}${GREEN}██████  ███████ ███    ██ ███████ ██     ██  █████  ██      ${RESET}
${BOLD}${GREEN}██   ██ ██      ████   ██ ██      ██     ██ ██   ██ ██      ${RESET}
${BOLD}${GREEN}██████  █████   ██ ██  ██ █████   ██  █  ██ ███████ ██      ${RESET}
${BOLD}${GREEN}██   ██ ██      ██  ██ ██ ██       ██ ███  ██   ██ ██      ${RESET}
${BOLD}${GREEN}██   ██ ███████ ██   ████ ███████   ███ ███ ██   ██ ███████ ${RESET}

EOF
}

# ===== MAIN SCRIPT STARTS HERE =====

# Display the banner
print_banner

print_info "Welcome to the Hail Certificate Renewal Tool"
print_info "This script will update your TLS certificates for Hail services"
echo

# Check if the user is in the docker group
print_warning "Checking your docker permissions..."

if id -nG "$USER" | grep -qw "docker"; then
    print_success "You are in the docker group. Proceeding with the script."
    
    # Check for a folder named 'hail' in the current directory
    if [ ! -d "hail" ]; then
        print_warning "No 'hail' folder found. Cloning 'hail' from GitHub... ${DNA}"
        run_command "git clone https://github.com/populationgenomics/hail.git" \
                   "Cloning repository" \
                   "Repository cloned successfully" \
                   "Failed to clone repository"
        cd hail
    else
        print_warning "Found 'hail' folder. Updating from GitHub... ${DNA}"
        cd hail
        run_command "git switch main && git pull" \
                   "Updating repository" \
                   "Repository updated successfully" \
                   "Failed to update repository"
    fi

    # Setup gcloud credentials with progress indication
    print_warning "Setting up gcloud credentials... ${SERVER}"
    
    run_command "gcloud config set project hail-295901" \
               "Setting project" \
               "Project set successfully" \
               "Failed to set project"
               
    run_command "gcloud config set compute/zone australia-southeast1-b" \
               "Setting compute zone" \
               "Compute zone set successfully" \
               "Failed to set compute zone"
               
    run_command "gcloud auth configure-docker australia-southeast1-docker.pkg.dev" \
               "Configuring docker authentication" \
               "Docker authentication configured successfully" \
               "Failed to configure docker authentication"
               
    run_command "gcloud container clusters get-credentials vdc" \
               "Getting cluster credentials" \
               "Cluster credentials obtained successfully" \
               "Failed to get cluster credentials"

    # Generate certificates
    print_warning "Generating certificates... ${CERT}"
    cd letsencrypt
    
    print_info "Running certificate generation process, this may take a while..."
    if make run NAMESPACE=default; then
        print_success "Certificates generated successfully!"
    else
        print_error "Certificates could not be generated!"
        exit 1
    fi

    # Restart Hail services
    print_warning "Restarting Hail services... ${SERVER}"

    export HAIL=$HOME/hail
    print_info "Identifying services to restart..."

    SERVICES_TO_RESTART=$(python3 -c '
import os
import yaml
hail_dir = os.getenv("HAIL")
x = yaml.safe_load(open(f"{hail_dir}/tls/config.yaml"))["principals"]
print(",".join(x["name"] for x in x))')

    print_info "Restarting the following services: ${SERVICES_TO_RESTART}"
    
    if kubectl delete pods -l "app in ($SERVICES_TO_RESTART)"; then
        print_success "Hail services restarted successfully!"
    else
        print_error "Hail services could not be restarted!"
        exit 1
    fi

    # Verify the certificates
    print_warning "Verifying certificates..."
    echo
    echo "Certificate information:"
    echo "------------------------"
    echo | openssl s_client -servername batch.hail.populationgenomics.org.au \
                           -connect batch.hail.populationgenomics.org.au:443 2>/dev/null | \
          openssl x509 -noout -dates
    echo "------------------------"
    echo
    
    print_success "Certificate renewal process completed successfully! ${ROCKET}"
    print_warning "Remember to turn off the VM to save costs! ${MONEY}"

else
    print_error "You need to add your user to the docker group to continue!"
    print_error "You can add yourself to the docker group by running the following command:"
    echo "${BOLD}${YELLOW}    sudo usermod -aG docker \$USER${RESET}"
    print_error "After running this command, log out and log back in for the changes to take effect."
    exit 1
fi
