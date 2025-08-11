```bash
#!/bin/bash

# --- Script Configuration ---
# This is a robust backup and restore script for the Remnawave application.
# It is designed to be installed and run on the host server.

# Set to exit immediately if any command fails.
set -e

# --- Script Variables (Do not change manually) ---
INSTALL_DIR="/opt/rw-backup-restore"
BACKUP_DIR="$INSTALL_DIR/backup"
CONFIG_FILE="$INSTALL_DIR/config.env"
SCRIPT_NAME="backup-restore.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
RETAIN_BACKUPS_DAYS=7
SYMLINK_PATH="/usr/local/bin/rw-backup"
REMNALABS_ROOT_DIR=""
ENV_NODE_FILE=".env-node"
ENV_FILE=".env"
SCRIPT_REPO_URL="https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh"
SCRIPT_RUN_PATH="$(realpath "$0")"
GD_CLIENT_ID=""
GD_CLIENT_SECRET=""
GD_REFRESH_TOKEN=""
GD_FOLDER_ID=""
UPLOAD_METHOD="telegram"
CRON_TIMES=""
TG_MESSAGE_THREAD_ID=""
UPDATE_AVAILABLE=false
VERSION="1.1.0"

# --- Terminal Colors ---
# These are used for better visual feedback in the console.
# They are disabled if the script is not running in a terminal.
if [[ -t 0 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    GRAY=$'\e[37m'
    LIGHT_GRAY=$'\e[90m'
    CYAN=$'\e[36m'
    RESET=$'\e[0m'
    BOLD=$'\e[1m'
else
    RED=""
    GREEN=""
    YELLOW=""
    GRAY=""
    LIGHT_GRAY=""
    CYAN=""
    RESET=""
    BOLD=""
fi

# --- Helper Function: print_message ---
# Prints a message with a specific type and color.
print_message() {
    local type="$1"
    local message="$2"
    local color_code="$RESET"

    case "$type" in
        "INFO") color_code="$GRAY" ;;
        "SUCCESS") color_code="$GREEN" ;;
        "WARN") color_code="$YELLOW" ;;
        "ERROR") color_code="$RED" ;;
        "ACTION") color_code="$CYAN" ;;
        "LINK") color_code="$CYAN" ;;
        *) type="INFO" ;;
    esac

    echo -e "${color_code}[$type]${RESET} $message"
}

# --- Function: setup_symlink ---
# Creates a symbolic link for easy execution.
setup_symlink() {
    echo ""
    if [[ "$EUID" -ne 0 ]]; then
        print_message "WARN" "Root privileges are required to manage the symbolic link ${BOLD}${SYMLINK_PATH}${RESET}. Skipping setup."
        return 1
    fi

    if [[ -L "$SYMLINK_PATH" && "$(readlink -f "$SYMLINK_PATH")" == "$SCRIPT_PATH" ]]; then
        print_message "SUCCESS" "Symbolic link ${BOLD}${SYMLINK_PATH}${RESET} is already configured and points to ${BOLD}${SCRIPT_PATH}${RESET}."
        return 0
    fi

    print_message "INFO" "Creating or updating symbolic link ${BOLD}${SYMLINK_PATH}${RESET}..."
    rm -f "$SYMLINK_PATH"
    if [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        if ln -s "$SCRIPT_PATH" "$SYMLINK_PATH"; then
            print_message "SUCCESS" "Symbolic link ${BOLD}${SYMLINK_PATH}${RESET} successfully configured."
        else
            print_message "ERROR" "Failed to create symbolic link ${BOLD}${SYMLINK_PATH}${RESET}. Check permissions."
            return 1
        fi
    else
        print_message "ERROR" "Directory ${BOLD}$(dirname "$SYMLINK_PATH")${RESET} not found. Symbolic link not created."
        return 1
    fi
    echo ""
    return 0
}

# --- Function: install_dependencies ---
# Checks for and installs required packages.
install_dependencies() {
    print_message "INFO" "Checking for and installing required packages..."
    echo ""

    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Error: This script requires root privileges to install dependencies. Please run it with '${BOLD}sudo${RESET}' or as the '${BOLD}root${RESET}' user.${RESET}"
        exit 1
    fi

    if command -v apt-get &> /dev/null; then
        print_message "INFO" "Updating ${BOLD}apt${RESET} package list..."
        apt-get update -qq > /dev/null 2>&1 || { echo -e "${RED}❌ Error: Failed to update the ${BOLD}apt${RESET} package list. Check your internet connection.${RESET}"; exit 1; }
        apt-get install -y toilet figlet procps lsb-release whiptail curl gzip cron > /dev/null 2>&1 || { echo -e "${RED}❌ Error: Failed to install required packages. Check for installation errors.${RESET}"; exit 1; }
        print_message "SUCCESS" "All necessary packages are installed or already present on the system."
    else
        print_message "WARN" "Warning: Could not find the package manager ${BOLD}'apt-get'${RESET}. Dependencies may need to be installed manually."
        command -v curl &> /dev/null || { echo -e "${RED}❌ Error: ${BOLD}'curl'${RESET} not found. Install it manually.${RESET}"; exit 1; }
        command -v docker &> /dev/null || { echo -e "${RED}❌ Error: ${BOLD}'docker'${RESET} not found. Install it manually.${RESET}"; exit 1; }
        command -v gzip &> /dev/null || { echo -e "${RED}❌ Error: ${BOLD}'gzip'${RESET} not found. Install it manually.${RESET}"; exit 1; }
        print_message "SUCCESS" "Core dependencies (${BOLD}curl${RESET}, ${BOLD}docker${RESET}, ${BOLD}gzip${RESET}) found."
    fi
    echo ""
}

# --- Function: save_config ---
# Saves the current configuration to the config file.
save_config() {
    print_message "INFO" "Saving configuration to ${BOLD}${CONFIG_FILE}${RESET}..."
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DB_USER="$DB_USER"
UPLOAD_METHOD="$UPLOAD_METHOD"
GD_CLIENT_ID="$GD_CLIENT_ID"
GD_CLIENT_SECRET="$GD_CLIENT_SECRET"
GD_REFRESH_TOKEN="$GD_REFRESH_TOKEN"
GD_FOLDER_ID="$GD_FOLDER_ID"
CRON_TIMES="$CRON_TIMES"
REMNALABS_ROOT_DIR="$REMNALABS_ROOT_DIR"
TG_MESSAGE_THREAD_ID="$TG_MESSAGE_THREAD_ID"
EOF
    chmod 600 "$CONFIG_FILE" || { print_message "ERROR" "Failed to set access rights (600) for ${BOLD}${CONFIG_FILE}${RESET}. Check permissions."; exit 1; }
    print_message "SUCCESS" "Configuration saved."
}

# --- Function: load_or_create_config ---
# Loads an existing configuration or guides the user to create a new one.
load_or_create_config() {

    if [[ -f "$CONFIG_FILE" ]]; then
        print_message "INFO" "Loading configuration..."
        source "$CONFIG_FILE"
        echo ""

        UPLOAD_METHOD=${UPLOAD_METHOD:-telegram}
        DB_USER=${DB_USER:-postgres}
        CRON_TIMES=${CRON_TIMES:-}
        REMNALABS_ROOT_DIR=${REMNALABS_ROOT_DIR:-}
        TG_MESSAGE_THREAD_ID=${TG_MESSAGE_THREAD_ID:-}
        
        local config_updated=false

        if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
            print_message "WARN" "The configuration file is missing required variables for Telegram."
            print_message "ACTION" "Please enter the missing Telegram data (required):"
            echo ""
            print_message "INFO" "Create a Telegram bot in ${CYAN}@BotFather${RESET} and get the API Token"
            [[ -z "$BOT_TOKEN" ]] && read -rp "    Enter API Token: " BOT_TOKEN
            echo ""
            print_message "INFO" "Enter the Chat ID (for sending to a group) or your Telegram ID (for sending directly to the bot)"
            echo -e "        You can find your Chat ID/Telegram ID using this bot ${CYAN}@username_to_id_bot${RESET}"
            [[ -z "$CHAT_ID" ]] && read -rp "    Enter ID: " CHAT_ID
            echo ""
            print_message "INFO" "Optional: to send to a specific topic in a group, enter the topic ID (Message Thread ID)"
            echo -e "        Leave empty for the general chat or for sending directly to the bot"
            read -rp "    Enter Message Thread ID: " TG_MESSAGE_THREAD_ID
            echo ""
            config_updated=true
        fi

        [[ -z "$DB_USER" ]] && read -rp "    Enter your DB username (default is postgres): " DB_USER
        DB_USER=${DB_USER:-postgres}
        config_updated=true
        echo ""
        
        if [[ -z "$REMNALABS_ROOT_DIR" ]]; then
            print_message "ACTION" "Where is your Remnawave panel installed/being installed?"
            echo "    1. /opt/remnawave"
            echo "    2. /root/remnawave"
            echo "    3. /opt/stacks/remnawave"
            echo ""
            local remnawave_path_choice
            while true; do
                read -rp "    ${GREEN}[?]${RESET} Select an option: " remnawave_path_choice
                case "$remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    *) print_message "ERROR" "Invalid input." ;;
                esac
            done
            config_updated=true
            echo ""
        fi


        if [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "Incomplete data for Google Drive found in the configuration file."
                print_message "WARN" "The upload method will be changed to ${BOLD}Telegram${RESET}."
                UPLOAD_METHOD="telegram"
                config_updated=true
            fi
        fi

        if [[ "$UPLOAD_METHOD" == "google_drive" && ( -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ) ]]; then
            print_message "WARN" "The configuration file is missing required variables for Google Drive."
            print_message "ACTION" "Please enter the missing data for Google Drive:"
            echo ""
            echo "If you don't have Client ID and Client Secret tokens"
            local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                print_message "LINK" "Check out this guide: ${CYAN}${guide_url}${RESET}"
                echo ""
            [[ -z "$GD_CLIENT_ID" ]] && read -rp "    Enter Google Client ID: " GD_CLIENT_ID
            [[ -z "$GD_CLIENT_SECRET" ]] && read -rp "    Enter Google Client Secret: " GD_CLIENT_SECRET
            clear
            
            if [[ -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "WARN" "To get the Refresh Token, you need to authorize in a browser."
                print_message "INFO" "Open the following link in a browser, authorize, and copy the code:"
                echo ""
                local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                print_message "INFO" "${CYAN}${auth_url}${RESET}"
                echo ""
                read -rp "    Enter the code from the browser: " AUTH_CODE
                
                print_message "INFO" "Getting Refresh Token..."
                local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                    -d client_id="$GD_CLIENT_ID" \
                    -d client_secret="$GD_CLIENT_SECRET" \
                    -d code="$AUTH_CODE" \
                    -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                    -d grant_type="authorization_code")
                
                GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                
                if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                    print_message "ERROR" "Failed to get Refresh Token. Check the Client ID, Client Secret, and the 'Code' you entered."
                    print_message "WARN" "Since the Google Drive setup is incomplete, the upload method will be changed to ${BOLD}Telegram${RESET}."
                    UPLOAD_METHOD="telegram"
                    config_updated=true
                fi
            fi
            echo
                    echo "    📁 To specify a Google Drive folder:"
                    echo "    1. Create and open the desired folder in your browser."
                    echo "    2. Look at the link in the address bar, it looks like this:"
                    echo "       https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                    echo "    3. Copy the part after /folders/ — this is the Folder ID:"
                    echo "    4. If you leave the field empty, the backup will be sent to the root folder of Google Drive."
                    echo

                    read -rp "    Enter Google Drive Folder ID (leave empty for the root folder): " GD_FOLDER_ID
            config_updated=true
            echo ""
        fi

        if $config_updated; then
            save_config
            print_message "SUCCESS" "Configuration supplemented and saved in ${BOLD}${CONFIG_FILE}${RESET}"
        else
            print_message "SUCCESS" "Configuration successfully loaded from ${BOLD}${CONFIG_FILE}${RESET}."
        fi

    else
        if [[ "$SCRIPT_RUN_PATH" != "$SCRIPT_PATH" ]]; then
            print_message "INFO" "Configuration not found. The script was launched from a temporary location."
            print_message "INFO" "Moving the script to the main installation directory: ${BOLD}${SCRIPT_PATH}${RESET}..."
            mkdir -p "$INSTALL_DIR" || { print_message "ERROR" "Failed to create installation directory ${BOLD}${INSTALL_DIR}${RESET}. Check permissions."; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_message "ERROR" "Failed to create backup directory ${BOLD}${BACKUP_DIR}${RESET}. Check permissions."; exit 1; }

            if mv "$SCRIPT_RUN_PATH" "$SCRIPT_PATH"; then
                chmod +x "$SCRIPT_PATH"
                clear
                print_message "SUCCESS" "Script successfully moved to ${BOLD}${SCRIPT_PATH}${RESET}."
                print_message "ACTION" "Restarting the script from the new location to complete the setup."
                exec "$SCRIPT_PATH" "$@"
                exit 0
            else
                print_message "ERROR" "Failed to move the script to ${BOLD}${SCRIPT_PATH}${RESET}. Check permissions."
                exit 1
            fi
        else
            print_message "INFO" "Configuration not found, creating a new one..."
            echo ""
            print_message "INFO" "Create a Telegram bot in ${CYAN}@BotFather${RESET} and get the API Token"
            read -rp "    Enter API Token: " BOT_TOKEN
            echo ""
            print_message "INFO" "Enter the Chat ID (for sending to a group) or your Telegram ID (for sending directly to the bot)"
            echo -e "        You can find your Chat ID/Telegram ID using this bot ${CYAN}@username_to_id_bot${RESET}"
            read -rp "    Enter ID: " CHAT_ID
            echo ""
            print_message "INFO" "Optional: to send to a specific topic in a group, enter the topic ID (Message Thread ID)"
            echo -e "        Leave empty for the general chat or for sending directly to the bot"
            read -rp "    Enter Message Thread ID: " TG_MESSAGE_THREAD_ID
            echo ""
            read -rp "    Enter your PostgreSQL username (default is postgres): " DB_USER
            DB_USER=${DB_USER:-postgres}
            echo ""

            print_message "ACTION" "Where is your Remnawave panel installed/being installed?"
            echo "    1. /opt/remnawave"
            echo "    2. /root/remnawave"
            echo "    3. /opt/stacks/remnawave"
            echo ""
            local remnawave_path_choice
            while true; do
                read -rp "    ${GREEN}[?]${RESET} Select an option: " remnawave_path_choice
                case "$remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    *) print_message "ERROR" "Invalid input." ;;
                esac
            done
            echo ""

            mkdir -p "$INSTALL_DIR" || { print_message "ERROR" "Failed to create installation directory ${BOLD}${INSTALL_DIR}${RESET}. Check permissions."; exit 1; }
            mkdir -p "$BACKUP_DIR" || { print_message "ERROR" "Failed to create backup directory ${BOLD}${BACKUP_DIR}${RESET}. Check permissions."; exit 1; }
            save_config
            print_message "SUCCESS" "New configuration saved in ${BOLD}${CONFIG_FILE}${RESET}"
        fi
    fi
    echo ""
}

# --- Helper Function: escape_markdown_v2 ---
# Escapes special characters for Telegram's MarkdownV2 format.
escape_markdown_v2() {
    local text="$1"
    echo "$text" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/_/\\_/g' \
        -e 's/\[/\\[/g' \
        -e 's/\]/\\]/g' \
        -e 's/(/\\(/g' \
        -e 's/)/\\)/g' \
        -e 's/~/\~/g' \
        -e 's/`/\\`/g' \
        -e 's/>/\\>/g' \
        -e 's/#/\\#/g' \
        -e 's/+/\\+/g' \
        -e 's/-/\\-/g' \
        -e 's/=/\\=/g' \
        -e 's/|/\\|/g' \
        -e 's/{/\\{/g' \
        -e 's/}/\\}/g' \
        -e 's/\./\\./g' \
        -e 's/!/\!/g'
}

# --- Function: get_remnawave_version ---
# Retrieves the version of the Remnawave application from package.json within the Docker container.
get_remnawave_version() {
    local version_output
    version_output=$(docker exec remnawave sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json
 2>/dev/null)
    if [[ -z "$version_output" ]]; then
        echo "not specified"
    else
        echo "$version_output"
    fi
}

# --- Function: send_telegram_message ---
# Sends a simple text message to Telegram.
send_telegram_message() {
    local message="$1"
    local parse_mode="${2:-MarkdownV2}"
    local escaped_message
    escaped_message=$(escape_markdown_v2 "$message")

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        print_message "ERROR" "Telegram BOT_TOKEN or CHAT_ID is not configured. Message not sent."
        return 1
    fi

    local data_params=(
        -d chat_id="$CHAT_ID"
        -d text="$escaped_message"
        -d parse_mode="$parse_mode"
    )

    if [[ -n "$TG_MESSAGE_THREAD_ID" ]]; then
        data_params+=(-d message_thread_id="$TG_MESSAGE_THREAD_ID")
    fi

    local http_code=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        "${data_params[@]}" \
        -w "%{http_code}" -o /dev/null 2>&1)

    if [[ "$http_code" -eq 200 ]]; then
        return 0
    else
        echo -e "${RED}❌ Error sending message to Telegram. HTTP code: ${BOLD}$http_code${RESET}. Make sure ${BOLD}BOT_TOKEN${RESET} and ${BOLD}CHAT_ID${RESET} are correct.${RESET}"
        return 1
    fi
}

# --- Function: send_telegram_document ---
# Sends a file as a document to Telegram.
send_telegram_document() {
    local file_path="$1"
    local caption="$2"
    local parse_mode="MarkdownV2"
    local escaped_caption
    escaped_caption=$(escape_markdown_v2 "$caption")

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        print_message "ERROR" "Telegram BOT_TOKEN or CHAT_ID is not configured. Document not sent."
        return 1
    fi

    local form_params=(
        -F chat_id="$CHAT_ID"
        -F document=@"$file_path"
        -F parse_mode="$parse_mode"
        -F caption="$escaped_caption"
    )

    if [[ -n "$TG_MESSAGE_THREAD_ID" ]]; then
        form_params+=(-F message_thread_id="$TG_MESSAGE_THREAD_ID")
    fi

    local api_response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        "${form_params[@]}" \
        -w "%{http_code}" -o /dev/null 2>&1)

    local curl_status=$?

    if [ $curl_status -ne 0 ]; then
        echo -e "${RED}❌ ${BOLD}CURL${RESET} error while sending document to Telegram. Exit code: ${BOLD}$curl_status${RESET}. Check network connection.${RESET}"
        return 1
    fi

    local http_code="${api_response: -3}"

    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        echo -e "${RED}❌ Telegram API returned an HTTP error. Code: ${BOLD}$http_code${RESET}. Response: ${BOLD}$api_response${RESET}. The file may be too large or ${BOLD}BOT_TOKEN${RESET}/${BOLD}CHAT_ID${RESET} may be incorrect.${RESET}"
        return 1
    fi
}

# --- Function: get_google_access_token ---
# Requests a new Google Drive Access Token using the Refresh Token.
get_google_access_token() {
    if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
        print_message "ERROR" "Google Drive Client ID, Client Secret, or Refresh Token is not configured."
        return 1
    fi

    local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
        -d client_id="$GD_CLIENT_ID" \
        -d client_secret="$GD_CLIENT_SECRET" \
        -d refresh_token="$GD_REFRESH_TOKEN" \
        -d grant_type="refresh_token")
    
    local access_token=$(echo "$token_response" | jq -r .access_token 2>/dev/null)
    local expires_in=$(echo "$token_response" | jq -r .expires_in 2>/dev/null)

    if [[ -z "$access_token" || "$access_token" == "null" ]]; then
        local error_msg=$(echo "$token_response" | jq -r .error_description 2>/dev/null)
        print_message "ERROR" "Failed to get Google Drive Access Token. The Refresh Token may be expired or invalid. Error: ${error_msg:-Unknown error}."
        print_message "ACTION" "Please reconfigure Google Drive in the 'Configure upload method' menu."
        return 1
    fi
    echo "$access_token"
    return 0
}

# --- Function: send_google_drive_document ---
# Uploads a file to Google Drive.
send_google_drive_document() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local access_token=$(get_google_access_token)

    if [[ -z "$access_token" ]]; then
        print_message "ERROR" "Failed to upload backup to Google Drive: Access Token not received."
        return 1
    fi

    local mime_type="application/gzip"
    local upload_url="https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"

    local metadata_file=$(mktemp)
    
    local metadata="{\"name\": \"$file_name\", \"mimeType\": \"$mime_type\""
    if [[ -n "$GD_FOLDER_ID" ]]; then
        metadata="${metadata}, \"parents\": [\"$GD_FOLDER_ID\"]"
    fi
    metadata="${metadata}}"
    
    echo "$metadata" > "$metadata_file"

    local response=$(curl -s -X POST "$upload_url" \
        -H "Authorization: Bearer $access_token" \
        -F "metadata=@$metadata_file;type=application/json" \
        -F "file=@$file_path;type=$mime_type")

    rm -f "$metadata_file"

    local file_id=$(echo "$response" | jq -r .id 2>/dev/null)
    local error_message=$(echo "$response" | jq -r .error.message 2>/dev/null)
    local error_code=$(echo "$response" | jq -r .error.code 2>/dev/null)

    if [[ -n "$file_id" && "$file_id" != "null" ]]; then
        return 0
    else
        print_message "ERROR" "Error uploading to Google Drive. Code: ${error_code:-Unknown}. Message: ${error_message:-Unknown error}. Full API response: ${response}"
        return 1
    fi
}

# --- Function: create_backup ---
# Main function to create the backup, archive it, and send it.
create_backup() {
    print_message "INFO" "Starting the backup process..."
    echo ""

    REMNALABS_VERSION=$(get_remnawave_version)
    TIMESTAMP=$(date +%Y-%m-%d"_"%H_%M_%S)
    BACKUP_FILE_DB="dump_${TIMESTAMP}.sql.gz"
    BACKUP_FILE_FINAL="remnawave_backup_${TIMESTAMP}.tar.gz"
    ENV_NODE_PATH="$REMNALABS_ROOT_DIR/$ENV_NODE_FILE"
    ENV_PATH="$REMNALABS_ROOT_DIR/$ENV_FILE"

    mkdir -p "$BACKUP_DIR" || { echo -e "${RED}❌ Error: Failed to create backup directory. Check permissions.${RESET}"; send_telegram_message "❌ Error: Failed to create backup directory ${BOLD}$BACKUP_DIR${RESET}." "None"; exit 1; }

    if ! docker inspect remnawave-db > /dev/null 2>&1 || ! docker container inspect -f '{{.State.Running}}' remnawave-db 2>/dev/null | grep -q "true"; then
        echo -e "${RED}❌ Error: The container ${BOLD}'remnawave-db'${RESET} was not found or is not running. Cannot create a database backup.${RESET}"
        local error_msg="❌ Error: The container ${BOLD}'remnawave-db'${RESET} was not found or is not running. Failed to create backup."
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Uploading to Google Drive is not possible due to the DB container error."
        fi
        exit 1
    fi
    print_message "INFO" "Creating and compressing PostgreSQL dump to a file..."
    if ! docker exec -t "remnawave-db" pg_dumpall -c -U "$DB_USER" | gzip -9 > "$BACKUP_DIR/$BACKUP_FILE_DB"; then
        STATUS=$?
        echo -e "${RED}❌ Error creating PostgreSQL dump. Exit code: ${BOLD}$STATUS${RESET}. Check the DB username and container access.${RESET}"
        local error_msg="❌ Error creating PostgreSQL dump. Exit code: ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Uploading to Google Drive is not possible due to the DB dump error."
        fi
        exit $STATUS
    fi
    print_message "SUCCESS" "PostgreSQL dump successfully created."
    echo ""
    print_message "INFO" "Archiving the backup to a file..."
    
    FILES_TO_ARCHIVE=("$BACKUP_FILE_DB")
    
    if [ -f "$ENV_NODE_PATH" ]; then
        print_message "INFO" "Found file ${BOLD}${ENV_NODE_FILE}${RESET}. Adding it to the archive."
        cp "$ENV_NODE_PATH" "$BACKUP_DIR/" || { 
            echo -e "${RED}❌ Error copying ${BOLD}${ENV_NODE_FILE}${RESET} for backup.${RESET}"; 
            local error_msg="❌ Error: Failed to copy ${BOLD}${ENV_NODE_FILE}${RESET} for backup."
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then send_telegram_message "$error_msg" "None"; fi
            exit 1; 
        }
        FILES_TO_ARCHIVE+=("$ENV_NODE_FILE")
    else
        print_message "WARN" "File ${BOLD}${ENV_NODE_FILE}${RESET} not found. Continuing without it."
    fi

    if [ -f "$ENV_PATH" ]; then
        print_message "INFO" "Found file ${BOLD}${ENV_FILE}${RESET}. Adding it to the archive."
        cp "$ENV_PATH" "$BACKUP_DIR/" || { 
            echo -e "${RED}❌ Error copying ${BOLD}${ENV_FILE}${RESET} for backup.${RESET}"; 
            local error_msg="❌ Error: Failed to copy ${BOLD}${ENV_FILE}${RESET} for backup."
            if [[ "$UPLOAD_METHOD" == "telegram" ]]; then send_telegram_message "$error_msg" "None"; fi
            exit 1; 
        }
        FILES_TO_ARCHIVE+=("$ENV_FILE")
    else
        print_message "WARN" "File ${BOLD}${ENV_FILE}${RESET} not found at path. Continuing without it."
    fi
    echo ""

    if ! tar -czf "$BACKUP_DIR/$BACKUP_FILE_FINAL" -C "$BACKUP_DIR" "${FILES_TO_ARCHIVE[@]}"; then
        STATUS=$?
        echo -e "${RED}❌ Error archiving the backup. Exit code: ${BOLD}$STATUS${RESET}. Check for free space and permissions.${RESET}"
        local error_msg="❌ Error archiving the backup. Exit code: ${BOLD}${STATUS}${RESET}"
        if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
            send_telegram_message "$error_msg" "None"
        elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
            print_message "ERROR" "Uploading to Google Drive is not possible due to the archiving error."
        fi
        exit $STATUS
    fi
    print_message "SUCCESS" "Backup archive successfully created: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}"
    echo ""

    print_message "INFO" "Cleaning up temporary backup files..."
    rm -f "$BACKUP_DIR/$BACKUP_FILE_DB"
    rm -f "$BACKUP_DIR/$ENV_NODE_FILE"
    rm -f "$BACKUP_DIR/$ENV_FILE"
    print_message "SUCCESS" "Temporary files deleted."
    echo ""

    print_message "INFO" "Sending backup (${UPLOAD_METHOD})..."
    local DATE=$(date +'%Y-%m-%d %H:%M:%S')
    local caption_text=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *Backup successfully created*\n🌊 *Remnawave:* '"${REMNALABS_VERSION}"$'\n📅 *Date:* '"${DATE}"
```
# ... (code for backup and upload logic) ...

# Check if the final backup file exists.
if [[ -f "$BACKUP_DIR/$BACKUP_FILE_FINAL" ]]; then
    # If the upload method is Telegram.
    if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
        # Try to send the document to Telegram.
        if send_telegram_document "$BACKUP_DIR/$BACKUP_FILE_FINAL" "$caption_text"; then
            print_message "SUCCESS" "Backup was successfully sent to Telegram."
        else
            echo -e "${RED}❌ Error sending the backup to Telegram. Check the Telegram API settings (token, chat ID).${RESET}"
        fi
    # If the upload method is Google Drive.
    elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
        # Try to send the document to Google Drive.
        if send_google_drive_document "$BACKUP_DIR/$BACKUP_FILE_FINAL"; then
            print_message "SUCCESS" "Backup was successfully sent to Google Drive."
            # Create a success message for Telegram.
            local tg_success_message=$'💾 #backup_success\n➖➖➖➖➖➖➖➖➖\n✅ *Backup was successfully created and sent to Google Drive*\n🌊 *Remnawave:* '"${REMNAWAVE_VERSION}"$'\n📅 *Date:* '"${DATE}"
            # Try to send the success notification to Telegram.
            if send_telegram_message "$tg_success_message"; then
                print_message "SUCCESS" "Notification about the successful upload to Google Drive was sent to Telegram."
            else
                print_message "ERROR" "Failed to send a notification to Telegram after uploading to Google Drive."
            fi
        else
            # Print an error message if Google Drive upload fails.
            echo -e "${RED}❌ Error sending the backup to Google Drive. Check the Google Drive API settings.${RESET}"
            send_telegram_message "❌ Error: Failed to send backup to Google Drive. Details are in the server logs." "None"
        fi
    else
        # Handle an unknown upload method.
        print_message "WARN" "Unknown upload method: ${BOLD}${UPLOAD_METHOD}${RESET}. Backup not sent."
        send_telegram_message "❌ Error: Unknown backup upload method: ${BOLD}${UPLOAD_METHOD}${RESET}. File: ${BOLD}${BACKUP_FILE_FINAL}${RESET} was not sent." "None"
    fi
else
    # Handle the case where the backup file doesn't exist.
    echo -e "${RED}❌ Error: The final backup file was not found after creation: ${BOLD}${BACKUP_DIR}/${BACKUP_FILE_FINAL}${RESET}. Sending is not possible.${RESET}"
    local error_msg="❌ Error: The backup file was not found after creation: ${BOLD}${BACKUP_FILE_FINAL}${RESET}"
    if [[ "$UPLOAD_METHOD" == "telegram" ]]; then
        send_telegram_message "$error_msg" "None"
    elif [[ "$UPLOAD_METHOD" == "google_drive" ]]; then
        print_message "ERROR" "Sending to Google Drive is not possible: backup file not found."
    fi
    exit 1
fi
echo ""

# Apply backup retention policy.
print_message "INFO" "Applying backup retention policy (keeping backups from the last ${BOLD}${RETAIN_BACKUPS_DAYS}${RESET} days)..."
find "$BACKUP_DIR" -maxdepth 1 -name "remnawave_backup_*.tar.gz" -mtime +$RETAIN_BACKUPS_DAYS -delete
print_message "SUCCESS" "Retention policy applied. Old backups have been deleted."
echo ""

# Check for script updates in the background.
{
    check_update_status >/dev/null 2>&1
    if [[ "$UPDATE_AVAILABLE" == true ]]; then
        local CURRENT_VERSION="$VERSION"
        local REMOTE_VERSION_LATEST

        # Get the latest version from GitHub.
        REMOTE_VERSION_LATEST=$(curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | grep -m 1 "^VERSION=" | cut -d'"' -f2)

        if [[ -n "$REMOTE_VERSION_LATEST" ]]; then
            local update_msg=$'⚠️ *Script update is available*\n🔄 *Current version:* '"${CURRENT_VERSION}"$'\n🆕 *Latest version:* '"${REMOTE_VERSION_LATEST}"$'\n\n📥 Update via the *"Script Update"* option in the main menu'
            send_telegram_message "$update_msg" >/dev/null 2>&1
        fi
    fi
} &
}

# Function to set up automatic sending.
setup_auto_send() {
    echo ""
    # Check for root privileges.
    if [[ $EUID -ne 0 ]]; then
        print_message "WARN" "Root privileges are required to configure cron. Please run with '${BOLD}sudo'${RESET}.${RESET}"
        read -rp "Press Enter to continue..."
        return
    fi
    while true; do
        clear
        echo -e "${GREEN}${BOLD}Configure Automatic Sending${RESET}"
        echo ""
        # Show current cron status.
        if [[ -n "$CRON_TIMES" ]]; then
            print_message "INFO" "Automatic sending is configured for: ${BOLD}${CRON_TIMES}${RESET} UTC+0."
        else
            print_message "INFO" "Automatic sending is ${BOLD}off${RESET}."
        fi
        echo ""
        echo "    1. Enable/Overwrite automatic backup sending"
        echo "    2. Disable automatic backup sending"
        echo ""
        echo "    0. Return to the main menu"
        echo ""
        read -rp "${GREEN}[?]${RESET} Choose an option: " choice
        echo ""
        case $choice in
            1)
                # ... (time conversion logic for cron) ...

                echo "Enter the desired sending time in UTC+0 (e.g., 08:00)"
                read -rp "You can specify multiple times separated by a space: " times
                
                # ... (validation and processing of user input) ...

                if [ "$invalid_format" = true ] || [ ${#cron_times_to_write[@]} -eq 0 ]; then
                    print_message "ERROR" "Automatic sending was not configured due to time input errors. Please try again."
                    continue
                fi

                print_message "INFO" "Configuring the cron task for automatic sending..."
                
                # ... (cron job setup logic) ...
                
                if crontab "$temp_crontab_file"; then
                    print_message "SUCCESS" "The cron task for automatic sending was successfully installed."
                else
                    print_message "ERROR" "Failed to install the cron task. Check permissions and crontab availability."
                fi

                # ... (cleanup and config saving) ...
                print_message "SUCCESS" "Automatic sending is set for: ${BOLD}${CRON_TIMES}${RESET} UTC+0."
                ;;
            2)
                print_message "INFO" "Disabling automatic sending..."
                # Remove the cron job.
                (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -
                
                # ... (cleanup and config saving) ...
                print_message "SUCCESS" "Automatic sending was successfully disabled."
                ;;
            0) break ;;
            *) print_message "ERROR" "Invalid input. Please choose one of the available options." ;;
        esac
        echo ""
        read -rp "Press Enter to continue..."
    done
    echo ""
}
    
# Function to restore a backup.
restore_backup() {
    clear
    echo "${GREEN}${BOLD}Restore from Backup${RESET}"
    echo ""
    print_message "INFO" "Place the backup file in the folder: ${BOLD}${BACKUP_DIR}${RESET}"

    # ... (file path definitions and checks for backup files) ...

    if ! compgen -G "$BACKUP_DIR/remnawave_backup_*.tar.gz" > /dev/null; then
        print_message "ERROR" "Error: No backup files found in ${BOLD}${BACKUP_DIR}${RESET}. Please place a backup file in this directory."
        read -rp "Press Enter to return to the menu..."
        return 1
    fi

    # ... (sorting and listing backups) ...

    if [ ${#SORTED_BACKUP_FILES[@]} -eq 0 ]; then
        print_message "ERROR" "Error: No backup files found in ${BOLD}${BACKUP_DIR}${RESET}."
        read -rp "Press Enter to return to the menu..."
        return 1
    fi

    echo ""
    echo "Choose a file to restore:"
    # ... (displaying list of backup files) ...
    echo ""
    echo "    0) Return to the main menu"
    echo ""

    # ... (user input and validation for file selection) ...

    echo ""
    print_message "WARN" "The restore operation will completely overwrite the current database."
    print_message "INFO" "In the script's configuration, you specified the database username as: ${BOLD}${GREEN}${DB_USER}${RESET}"
    read -rp "$(echo -e "${GREEN}[?]${RESET} Enter ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET} to continue: ")" db_user_confirm
    if [[ "$db_user_confirm" != "y" ]]; then
        print_message "INFO" "The restore operation was canceled by the user."
        read -rp "Press Enter to return to the menu..."
        return
    fi

    clear
    print_message "INFO" "Starting the full database reset and restore process..."
    echo ""

    print_message "INFO" "Stopping containers and deleting the database volume..."
    # ... (docker operations to stop containers and remove volume) ...
    
    echo ""

    print_message "INFO" "Unpacking the backup archive..."
    # ... (unpacking the archive and error handling) ...
    print_message "SUCCESS" "The archive was successfully unpacked into a temporary directory."
    echo ""

    # ... (handling of .env files from the backup) ...
    
    print_message "INFO" "Starting the database container, please wait..."
    # ... (docker operations to start the database and wait for it to be ready) ...
    print_message "SUCCESS" "The database is ready."
    echo ""
    print_message "INFO" "Restoring the database from the dump..."
    
    # ... (database restoration logic) ...

    if ! docker exec -i remnawave-db psql -q -U postgres -d postgres > /dev/null 2> "$temp_restore_dir/restore_errors.log" < "$DUMP_FILE"; then
        print_message "ERROR" "Error restoring the database dump."

        echo ""
        print_message "WARN" "${YELLOW}Restore error log:${RESET}"
        cat "$temp_restore_dir/restore_errors.log"

        # ... (cleanup and return) ...
        return 1
    fi

    print_message "SUCCESS" "The database was successfully restored."
    echo ""

    print_message "INFO" "Deleting temporary restore files..."
    # ... (cleanup of temporary directory) ...
    echo ""

    print_message "INFO" "Starting all containers..."
    docker compose up -d
    echo ""

    print_message "SUCCESS" "Restore complete. All containers have been started."

    # ... (send success notification to Telegram) ...
    
    read -rp "Press Enter to continue..."
    return
}

# Function to update the script.
update_script() {
    print_message "INFO" "Starting the update check process..."
    echo ""
    # Check for root privileges.
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}⛔ Root privileges are required to update the script. Please run with '${BOLD}sudo'${RESET}.${RESET}"
        read -rp "Press Enter to continue..."
        return
    fi

    print_message "INFO" "Getting the latest script version information from GitHub..."
    # ... (fetch latest version from GitHub) ...

    if [[ -z "$REMOTE_VERSION" ]]; then
        print_message "ERROR" "Failed to extract version information from the remote script. The format of the VERSION variable may have changed."
        read -rp "Press Enter to continue..."
        return
    fi

    print_message "INFO" "Current version: ${BOLD}${YELLOW}${VERSION}${RESET}"
    print_message "INFO" "Available version: ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}"
    echo ""

    # ... (version comparison logic) ...

    if compare_versions "$VERSION" "$REMOTE_VERSION"; then
        print_message "ACTION" "An update to version ${BOLD}${REMOTE_VERSION}${RESET} is available."
        echo -e -n "Do you want to update the script? Enter ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: "
        read -r confirm_update
        echo ""

        if [[ "${confirm_update,,}" != "y" ]]; then
            print_message "WARN" "Update canceled by the user. Returning to the main menu."
            read -rp "Press Enter to continue..."
            return
        fi
    else
        print_message "INFO" "You have the latest version of the script installed. An update is not required."
        read -rp "Press Enter to continue..."
        return
    fi

    # ... (downloading and validating the new script) ...
    
    print_message "INFO" "Deleting old script backups..."
}
# Delete old backup copies of the script
find "$(dirname "$SCRIPT_PATH")" -maxdepth 1 -name "${SCRIPT_NAME}.bak.*" -type f -delete
echo ""

# Create a new backup of the current script with a timestamp
local BACKUP_PATH_SCRIPT="${SCRIPT_PATH}.bak.$(date +%s)"
print_message "INFO" "Creating a backup of the current script..."
cp "$SCRIPT_PATH" "$BACKUP_PATH_SCRIPT" || {
    echo -e "${RED}❌ Failed to create a backup of ${BOLD}${SCRIPT_PATH}${RESET}. Update canceled.${RESET}"
    rm -f "$TEMP_SCRIPT_PATH"
    read -rp "Press Enter to continue..."
    return
}
echo ""

# Move the new script version from a temporary location
mv "$TEMP_SCRIPT_PATH" "$SCRIPT_PATH" || {
    echo -e "${RED}❌ Error moving the temporary file to ${BOLD}${SCRIPT_PATH}${RESET}. Please check permissions.${RESET}"
    echo -e "${YELLOW}⚠️ Restoring from backup ${BOLD}${BACKUP_PATH_SCRIPT}${RESET}...${RESET}"
    mv "$BACKUP_PATH_SCRIPT" "$SCRIPT_PATH"
    rm -f "$TEMP_SCRIPT_PATH"
    read -rp "Press Enter to continue..."
    return
}

# Set execute permissions for the updated script
chmod +x "$SCRIPT_PATH"
print_message "SUCCESS" "Script successfully updated to version ${BOLD}${GREEN}${REMOTE_VERSION}${RESET}."
echo ""
print_message "INFO" "The script will restart to apply changes..."
read -rp "Press Enter to restart."
exec "$SCRIPT_PATH" "$@"
exit 0
}
# Display a warning about what will be removed
print_message "WARN" "${YELLOW}WARNING!${RESET} The following will be removed: "
echo " - The script itself"
echo " - The installation directory and all backups"
echo " - The symbolic link (if it exists)"
echo " - Any cron jobs"
echo ""

# Ask for user confirmation
echo -e -n "Are you sure you want to continue? Enter ${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}: "
read -r confirm
echo ""

# If user does not confirm, cancel the operation
if [[ "${confirm,,}" != "y" ]]; then
    print_message "WARN" "Removal canceled."
    read -rp "Press Enter to continue..."
    return
fi

# Check for root privileges, as they are required for a full removal
if [[ "$EUID" -ne 0 ]]; then
    print_message "WARN" "Root privileges are required for a full removal. Please run with ${BOLD}sudo${RESET}."
    read -rp "Press Enter to continue..."
    return
fi

# Remove any existing cron jobs
print_message "INFO" "Removing cron jobs..."
if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH backup"; then
    (crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH backup") | crontab -
    print_message "SUCCESS" "Cron jobs for automatic backup removed."
else
    print_message "INFO" "Cron jobs for automatic backup not found."
fi
echo ""

# Remove the symbolic link
print_message "INFO" "Removing symbolic link..."
if [[ -L "$SYMLINK_PATH" ]]; then
    rm -f "$SYMLINK_PATH" && print_message "SUCCESS" "Symbolic link ${BOLD}${SYMLINK_PATH}${RESET} removed." || print_message "WARN" "Failed to remove symbolic link ${BOLD}${SYMLINK_PATH}${RESET}. Manual removal may be required."
elif [[ -e "$SYMLINK_PATH" ]]; then
    print_message "WARN" "${BOLD}${SYMLINK_PATH}${RESET} exists but is not a symbolic link. It is recommended to check and remove it manually."
else
    print_message "INFO" "Symbolic link ${BOLD}${SYMLINK_PATH}${RESET} not found."
fi
echo ""

# Remove the installation directory and all its contents
print_message "INFO" "Removing installation directory and all data..."
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR" && print_message "SUCCESS" "Installation directory ${BOLD}${INSTALL_DIR}${RESET} (including script, configuration, backups) removed." || echo -e "${RED}❌ Error removing directory ${BOLD}${INSTALL_DIR}${RESET}. Root privileges may be required, or the directory may be in use.${RESET}"
else
    print_message "INFO" "Installation directory ${BOLD}${INSTALL_DIR}${RESET} not found."
fi
exit 0
}
# Main loop for the configuration menu
while true; do
    clear
    echo -e "${GREEN}${BOLD}Configure Backup Upload Method${RESET}"
    echo ""
    print_message "INFO" "Current method: ${BOLD}${UPLOAD_METHOD^^}${RESET}"
    echo ""
    echo "    1. Set upload method to: Telegram"
    echo "    2. Set upload method to: Google Drive"
    echo ""
    echo "    0. Return to main menu"
    echo ""
    read -rp "${GREEN}[?]${RESET} Select an option: " choice
    echo ""

    case $choice in
        1) # Configure Telegram
            UPLOAD_METHOD="telegram"
            save_config
            print_message "SUCCESS" "Upload method set to ${BOLD}Telegram${RESET}."
            if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
                print_message "ACTION" "Please enter your Telegram details:"
                echo ""
                print_message "INFO" "Create a Telegram bot via ${CYAN}@BotFather${RESET} and get an API Token"
                read -rp "    Enter API Token: " BOT_TOKEN
                echo ""
                print_message "INFO" "You can find your ID using this bot on Telegram: ${CYAN}@userinfobot${RESET}"
                read -rp "    Enter your Telegram ID: " CHAT_ID
                save_config
                print_message "SUCCESS" "Telegram settings saved."
            fi
            ;;
        2) # Configure Google Drive
            UPLOAD_METHOD="google_drive"
            print_message "SUCCESS" "Upload method set to ${BOLD}Google Drive${RESET}."
            
            local gd_setup_successful=true

            if [[ -z "$GD_CLIENT_ID" || -z "$GD_CLIENT_SECRET" || -z "$GD_REFRESH_TOKEN" ]]; then
                print_message "ACTION" "Please enter your Google Drive API credentials."
                echo ""
                echo "If you don't have Client ID and Client Secret tokens"
                local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                print_message "LINK" "Study this guide: ${CYAN}${guide_url}${RESET}"
                read -rp "    Enter Google Client ID: " GD_CLIENT_ID
                read -rp "    Enter Google Client Secret: " GD_CLIENT_SECRET
                
                clear
                
                print_message "WARN" "To get a Refresh Token, you need to authorize in your browser."
                print_message "INFO" "Open the following link in your browser, log in, and copy the ${BOLD}code${RESET}:"
                echo ""
                local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                print_message "INFO" "${CYAN}${auth_url}${RESET}"
                echo ""
                read -rp "Enter the code from your browser: " AUTH_CODE
                
                print_message "INFO" "Getting Refresh Token..."
                local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                    -d client_id="$GD_CLIENT_ID" \
                    -d client_secret="$GD_CLIENT_SECRET" \
                    -d code="$AUTH_CODE" \
                    -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                    -d grant_type="authorization_code")
                
                GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                
                if [[ -z "$GD_REFRESH_TOKEN" || "$GD_REFRESH_TOKEN" == "null" ]]; then
                    print_message "ERROR" "Failed to get Refresh Token. Check the entered details."
                    print_message "WARN" "Setup incomplete, upload method will be changed to ${BOLD}Telegram${RESET}."
                    UPLOAD_METHOD="telegram"
                    gd_setup_successful=false
                else
                    print_message "SUCCESS" "Refresh Token successfully obtained."
                fi
                echo
                
                if $gd_setup_successful; then
                    echo "    📁 To specify a Google Drive folder:"
                    echo "    1. Create and open the desired folder in your browser."
                    echo "    2. Look at the link in the address bar, it looks like this:"
                    echo "       https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                    echo "    3. Copy the part after /folders/ — this is the Folder ID:"
                    echo "    4. If you leave the field empty, the backup will be sent to the root folder of Google Drive."
                    echo

                    read -rp "    Enter Google Drive Folder ID (leave empty for root folder): " GD_FOLDER_ID
                fi
            fi

            save_config

            if $gd_setup_successful; then
                print_message "SUCCESS" "Google Drive settings saved."
            else
                print_message "SUCCESS" "Upload method set to ${BOLD}Telegram${RESET}."
            fi
            ;;
        0) break ;;
        *) print_message "ERROR" "Invalid input. Please choose one of the options." ;;
    esac
    echo ""
    read -rp "Press Enter to continue..."
done
echo ""
}
# Main loop for the settings menu
while true; do
    clear
    echo -e "${GREEN}${BOLD}Change Script Configuration${RESET}"
    echo ""
    echo "    1. Telegram settings"
    echo "    2. Google Drive settings"
    echo "    3. PostgreSQL username"
    echo "    4. Remnawave path"
    echo ""
    echo "    0. Return to main menu"
    echo ""
    read -rp "${GREEN}[?]${RESET} Select an option: " choice
    echo ""

    case $choice in
        1) # Telegram settings submenu
            while true; do
                clear
                echo -e "${GREEN}${BOLD}Telegram Settings${RESET}"
                echo ""
                print_message "INFO" "Current API Token: ${BOLD}${BOT_TOKEN}${RESET}"
                print_message "INFO" "Current ID: ${BOLD}${CHAT_ID}${RESET}"
                print_message "INFO" "Current Message Thread ID: ${BOLD}${TG_MESSAGE_THREAD_ID:-Not set}${RESET}"
                echo ""
                echo "    1. Change API Token"
                echo "    2. Change ID"
                echo "    3. Change Message Thread ID (for group topics)"
                echo ""
                echo "    0. Back"
                echo ""
                read -rp "${GREEN}[?]${RESET} Select an option: " telegram_choice
                echo ""

                case $telegram_choice in
                    1)
                        print_message "INFO" "Create a Telegram bot via ${CYAN}@BotFather${RESET} and get an API Token"
                        read -rp "    Enter new API Token: " NEW_BOT_TOKEN
                        BOT_TOKEN="$NEW_BOT_TOKEN"
                        save_config
                        print_message "SUCCESS" "API Token successfully updated."
                        ;;
                    2)
                        print_message "INFO" "Enter Chat ID (for group) or your Telegram ID (for direct message)"
                        echo -e "        You can find your Chat ID/Telegram ID using this bot: ${CYAN}@username_to_id_bot${RESET}"
                        read -rp "    Enter new ID: " NEW_CHAT_ID
                        CHAT_ID="$NEW_CHAT_ID"
                        save_config
                        print_message "SUCCESS" "ID successfully updated."
                        ;;
                    3)
                        print_message "INFO" "Optional: to send to a specific group topic, enter the topic ID (Message Thread ID)"
                        echo -e "        Leave empty for the general chat or direct messages to the bot"
                        read -rp "    Enter Message Thread ID: " NEW_TG_MESSAGE_THREAD_ID
                        TG_MESSAGE_THREAD_ID="$NEW_TG_MESSAGE_THREAD_ID"
                        save_config
                        print_message "SUCCESS" "Message Thread ID successfully updated."
                        ;;
                    0) break ;;
                    *) print_message "ERROR" "Invalid input. Please choose one of the options." ;;
                esac
                echo ""
                read -rp "Press Enter to continue..."
            done
            ;;

        2) # Google Drive settings submenu
            while true; do
                clear
                echo -e "${GREEN}${BOLD}Google Drive Settings${RESET}"
                echo ""
                print_message "INFO" "Current Client ID: ${BOLD}${GD_CLIENT_ID:0:8}...${RESET}"
                print_message "INFO" "Current Client Secret: ${BOLD}${GD_CLIENT_SECRET:0:8}...${RESET}"
                print_message "INFO" "Current Refresh Token: ${BOLD}${GD_REFRESH_TOKEN:0:8}...${RESET}"
                print_message "INFO" "Current Drive Folder ID: ${BOLD}${GD_FOLDER_ID:-Root folder}${RESET}"
                echo ""
                echo "    1. Change Google Client ID"
                echo "    2. Change Google Client Secret"
                echo "    3. Change Google Refresh Token (reauthorization required)"
                echo "    4. Change Google Drive Folder ID"
                echo ""
                echo "    0. Back"
                echo ""
                read -rp "${GREEN}[?]${RESET} Select an option: " gd_choice
                echo ""

                case $gd_choice in
                    1)
                        echo "If you don't have Client ID and Client Secret tokens"
                        local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                        print_message "LINK" "Study this guide: ${CYAN}${guide_url}${RESET}"
                        read -rp "    Enter new Google Client ID: " NEW_GD_CLIENT_ID
                        GD_CLIENT_ID="$NEW_GD_CLIENT_ID"
                        save_config
                        print_message "SUCCESS" "Google Client ID successfully updated."
                        ;;
                    2)
                        echo "If you don't have Client ID and Client Secret tokens"
                        local guide_url="https://telegra.ph/Nastrojka-Google-API-06-02"
                        print_message "LINK" "Study this guide: ${CYAN}${guide_url}${RESET}"
                        read -rp "    Enter new Google Client Secret: " NEW_GD_CLIENT_SECRET
                        GD_CLIENT_SECRET="$NEW_GD_CLIENT_SECRET"
                        save_config
                        print_message "SUCCESS" "Google Client Secret successfully updated."
                        ;;
                    3)
                        clear
                        print_message "WARN" "To get a new Refresh Token, you need to authorize in your browser."
                        print_message "INFO" "Open the following link in your browser, log in, and copy the ${BOLD}code${RESET}:"
                        echo ""
                        local auth_url="https://accounts.google.com/o/oauth2/auth?client_id=${GD_CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive&response_type=code&access_type=offline"
                        print_message "LINK" "${CYAN}${auth_url}${RESET}"
                        echo ""
                        read -rp "Enter the code from your browser: " AUTH_CODE
                        
                        print_message "INFO" "Getting Refresh Token..."
                        local token_response=$(curl -s -X POST https://oauth2.googleapis.com/token \
                            -d client_id="$GD_CLIENT_ID" \
                            -d client_secret="$GD_CLIENT_SECRET" \
                            -d code="$AUTH_CODE" \
                            -d redirect_uri="urn:ietf:wg:oauth:2.0:oob" \
                            -d grant_type="authorization_code")
                        
                        NEW_GD_REFRESH_TOKEN=$(echo "$token_response" | jq -r .refresh_token 2>/dev/null)
                        
                        if [[ -z "$NEW_GD_REFRESH_TOKEN" || "$NEW_GD_REFRESH_TOKEN" == "null" ]]; then
                            print_message "ERROR" "Failed to get Refresh Token. Check the entered details."
                            print_message "WARN" "Setup incomplete."
                        else
                            GD_REFRESH_TOKEN="$NEW_GD_REFRESH_TOKEN"
                            save_config
                            print_message "SUCCESS" "Refresh Token successfully updated."
                        fi
                        ;;
                    4)
                        echo
                        echo "    📁 To specify a Google Drive folder:"
                        echo "    1. Create and open the desired folder in your browser."
                        echo "    2. Look at the link in the address bar, it looks like this:"
                        echo "       https://drive.google.com/drive/folders/1a2B3cD4eFmNOPqRstuVwxYz"
                        echo "    3. Copy the part after /folders/ — this is the Folder ID:"
                        echo "    4. If you leave the field empty, the backup will be sent to the root folder of Google Drive."
                        echo
                        read -rp "    Enter new Google Drive Folder ID (leave empty for root folder): " NEW_GD_FOLDER_ID
                        GD_FOLDER_ID="$NEW_GD_FOLDER_ID"
                        save_config
                        print_message "SUCCESS" "Google Drive Folder ID successfully updated."
                        ;;
                    0) break ;;
                    *) print_message "ERROR" "Invalid input. Please choose one of the options." ;;
                esac
                echo ""
                read -rp "Press Enter to continue..."
            done
            ;;
        3) # PostgreSQL username
            clear
            echo -e "${GREEN}${BOLD}PostgreSQL Username${RESET}"
            echo ""
            print_message "INFO" "Current PostgreSQL username: ${BOLD}${DB_USER}${RESET}"
            echo ""
            read -rp "    Enter new PostgreSQL username (default is postgres): " NEW_DB_USER
            DB_USER="${NEW_DB_USER:-postgres}"
            save_config
            print_message "SUCCESS" "PostgreSQL username successfully updated to ${BOLD}${DB_USER}${RESET}."
            echo ""
            read -rp "Press Enter to continue..."
            ;;
        4) # Remnawave path
            clear
            echo -e "${GREEN}${BOLD}Remnawave Path${RESET}"
            echo ""
            print_message "INFO" "Current Remnawave path: ${BOLD}${REMNALABS_ROOT_DIR}${RESET}"
            echo ""
            print_message "ACTION" "Choose a new path for the Remnawave panel:"
            echo "    1. /opt/remnawave"
            echo "    2. /root/remnawave"
            echo "    3. /opt/stacks/remnawave"
            echo ""
            local new_remnawave_path_choice
            while true; do
                read -rp "    ${GREEN}[?]${RESET} Select an option: " new_remnawave_path_choice
                case "$new_remnawave_path_choice" in
                    1) REMNALABS_ROOT_DIR="/opt/remnawave"; break ;;
                    2) REMNALABS_ROOT_DIR="/root/remnawave"; break ;;
                    3) REMNALABS_ROOT_DIR="/opt/stacks/remnawave"; break ;;
                    *) print_message "ERROR" "Invalid input." ;;
                esac
            done
            save_config
            print_message "SUCCESS" "Remnawave path successfully updated to ${BOLD}${REMNALABS_ROOT_DIR}${RESET}."
            echo ""
            read -rp "Press Enter to continue..."
            ;;
        0) break ;;
        *) print_message "ERROR" "Invalid input. Please choose one of the options." ;;
    esac
    echo ""
done
}
# Get the first 100 lines of the remote script to check its version
local TEMP_REMOTE_VERSION_FILE
TEMP_REMOTE_VERSION_FILE=$(mktemp)

if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_REMOTE_VERSION_FILE"; then
    UPDATE_AVAILABLE=false
    rm -f "$TEMP_REMOTE_VERSION_FILE"
    return
fi

# Extract the version number from the remote script
local REMOTE_VERSION
REMOTE_VERSION=$(grep -m 1 "^VERSION=" "$TEMP_REMOTE_VERSION_FILE" | cut -d'"' -f2)
rm -f "$TEMP_REMOTE_VERSION_FILE"

if [[ -z "$REMOTE_VERSION" ]]; then
    UPDATE_AVAILABLE=false
    return
fi

# Function to compare local and remote versions
compare_versions_for_check() {
    local v1="$1"
    local v2="$2"

    local v1_num="${v1//[^0-9.]/}"
    local v2_num="${v2//[^0-9.]/}"

    local v1_sfx="${v1//$v1_num/}"
    local v2_sfx="${v2//$v2_num/}"

    if [[ "$v1_num" == "$v2_num" ]]; then
        if [[ -z "$v1_sfx" && -n "$v2_sfx" ]]; then
            return 0
        elif [[ -n "$v1_sfx" && -z "$v2_sfx" ]]; then
            return 1
        elif [[ "$v1_sfx" < "$v2_sfx" ]]; then
            return 0
        else
            return 1
        fi
    else
        if printf '%s\n' "$v1_num" "$v2_num" | sort -V | head -n1 | grep -qx "$v1_num"; then
            return 0
        else
            return 1
        fi
    fi
}

# Set the UPDATE_AVAILABLE flag based on the version comparison
if compare_versions_for_check "$VERSION" "$REMOTE_VERSION"; then
    UPDATE_AVAILABLE=true
else
    UPDATE_AVAILABLE=false
fi
}
while true; do
    check_update_status
    clear
    echo -e "${GREEN}${BOLD}REMNAWAVE BACKUP & RESTORE by distillium${RESET} "
    if [[ "$UPDATE_AVAILABLE" == true ]]; then
        echo -e "${BOLD}${LIGHT_GRAY}Version: ${VERSION} ${YELLOW}(update available)${RESET}"
    else
        echo -e "${BOLD}${LIGHT_GRAY}Version: ${VERSION}${RESET}"
    fi
    echo ""
    echo "    1. Create a backup manually"
    echo "    2. Restore from a backup"
    echo ""
    echo "    3. Configure automatic sending and notifications"
    echo "    4. Configure upload method"
    echo "    5. Change script configuration"
    echo ""
    echo "    6. Update script"
    echo "    7. Remove script"
    echo ""
    echo "    0. Exit"
    echo -e "    —  Quick launch: ${BOLD}${GREEN}rw-backup${RESET} is available system-wide"
    echo ""

    read -rp "${GREEN}[?]${RESET} Select an option: " choice
    echo ""
    case $choice in
        1) create_backup ; read -rp "Press Enter to continue..." ;;
        2) restore_backup ;;
        3) setup_auto_send ;;
        4) configure_upload_method ;;
        5) configure_settings ;;
        6) update_script ;;
        7) remove_script ;;
        0) echo "Exiting..."; exit 0 ;;
        *) print_message "ERROR" "Invalid input. Please choose one of the options." ; read -rp "Press Enter to continue..." ;;
    esac
done
}
# Check if 'jq' is installed and install it if necessary
if ! command -v jq &> /dev/null; then
    print_message "INFO" "Installing 'jq' package for JSON parsing..."
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Error: 'jq' requires root privileges to install. Please install 'jq' manually (e.g., 'sudo apt-get install jq') or run the script with sudo.${RESET}"
        exit 1
    fi
    if command -v apt-get &> /dev/null; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y jq > /dev/null 2>&1 || { echo -e "${RED}❌ Error: Failed to install 'jq'.${RESET}"; exit 1; }
        print_message "SUCCESS" "'jq' successfully installed."
    else
        print_message "ERROR" "Could not find package manager 'apt-get'. Install 'jq' manually."
        exit 1
    fi
fi

# Check for command-line arguments and run the appropriate function
if [[ -z "$1" ]]; then
    # No arguments provided, show the main menu
    install_dependencies
    load_or_create_config
    setup_symlink
    main_menu
elif [[ "$1" == "backup" ]]; then
    # Run a direct backup
    load_or_create_config
    create_backup
elif [[ "$1" == "restore" ]]; then
    # Run a direct restore
    load_or_create_config
    restore_backup
elif [[ "$1" == "update" ]]; then
    # Run a direct update
    update_script
elif [[ "$1" == "remove" ]]; then
    # Run a direct removal
    remove_script
else
    # Invalid command-line argument
    echo -e "${RED}❌ Invalid usage. Available commands: ${BOLD}${0} [backup|restore|update|remove]${RESET}${RESET}"
    exit 1
fi
