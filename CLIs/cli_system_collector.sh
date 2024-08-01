#!/bin/bash
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[1;33m'
YELLOW='\033[0;33m'
NC='\033[0m' # no color

#Duration of test
test_duration=120

# Monitoring Options
monitoring_types=("CPU" "DISK" "RAM" "ALL")

# System Information
os_name=$(uname -s)
hostname=$(hostname)
hostname=${hostname//./_}

# Initialize arrays to hold the values
filesystems=()
sizes=()
useds=()
avails=()
cpu_data=()
ram_total=()
ram_used=()
ram_available=()

############################################################
terminal_size=$(stty size)
initial_rows=$(echo $terminal_size | cut -d ' ' -f 1)
initial_columns=$(echo $terminal_size | cut -d ' ' -f 2)
LOGO_VISIBLE=false
HEADER_VISIBLE=false
API_PROMPT_VISIBLE=false
MONITORING_TYPE_VISIBLE=false
############################################################

# Cursor control & section clearing
show_cursor() {
    printf "\033[?25h"
}

hide_cursor() {
    printf "\033[?25l"
}

move_cursor() {
    local row=$1
    local col=$2

    printf "\033[${row};${col}H"
}

handle_interruption() {
    printf "\n"
    printf "${RED}Script Interrupted. Exiting...\n${NC}"
    show_cursor
    sleep 1
    exit 1
}

clear_region() {
    local start_row=$1
    local end_row=$2
    local start_col=$3
    local end_col=$4

    hide_cursor
    for ((row=start_row; row<=end_row; row++)); do
        for ((col=start_col; col<=end_col; col++)); do
            move_cursor $row $col
            printf " "
        done
    done
    show_cursor
}

# Asciii art and display
mf() {
    cat << 'EOF'
 __  __      _        _      _____ _          
|  \/  | ___| |_ _ __(_) ___|  ___(_)_ __ ___ 
| |\/| |/ _ \ __| '__| |/ __| |_  | | '__/ _ \
| |  | |  __/ |_| |  | | (__|  _| | | | |  __/
|_|  |_|\___|\__|_|  |_|\___|_|   |_|_|  \___|
EOF
}


flame() (
    cat << 'EOF'
⠀⠀⠀⠀⠀⠀⢱⣆⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠈⣿⣷⡀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⢸⣿⣿⣷⣧⠀⠀⠀
⠀⠀⠀⠀⡀⢠⣿⡟⣿⣿⣿⡇⠀⠀
⠀⠀⠀⠀⣳⣼⣿⡏⢸⣿⣿⣿⢀⠀
⠀⠀⠀⣰⣿⣿⡿⠁⢸⣿⣿⡟⣼⡆
⢰⢀⣾⣿⣿⠟⠀⠀⣾⢿⣿⣿⣿⣿
⢸⣿⣿⣿⡏⠀⠀⠀⠃⠸⣿⣿⣿⡿
⢳⣿⣿⣿⠀⠀⠀⠀⠀⠀⢹⣿⡿⡁
⠀⠹⣿⣿⡄⠀⠀⠀⠀⠀⢠⣿⡞⠁
⠀⠀⠈⠛⢿⣄⠀⠀⠀⣠⠞⠋⠀⠀
⠀⠀⠀⠀⠀⠀⠉⠀⠀⠀⠀⠀⠀⠀
EOF
)

display_ascii_art() {
    local start_row=$1
    local start_col=$2
    local type=$3
    local ascii_art=$($4)

    hide_cursor
    IFS=$'\n' read -d '' -r -a lines <<< "$ascii_art"

    case $type in
        "mf")
            for ((i = 0; i < ${#lines[@]}; i++)); do
                move_cursor "$((start_row + i))" "$start_col"
                printf "${RED}${lines[i]}"
            done
            printf "${NC}"
            ;;
        "flame")
            local colors=(196 202 208 214 220 226)
            local num_colors=${#colors[@]}
            local num_lines=${#lines[@]}
            local color_step=$((num_lines / num_colors))

            for ((i = 0; i < num_lines; i++)); do
                local color_index=$((i / color_step))
                local color=${colors[color_index]}
                move_cursor "$((start_row + i))" "$start_col"
                printf "\e[38;5;%dm%s\e[0m\n" "$color" "${lines[i]}"
            done
            ;;
        * )
            printf "No ascii art found"
            ;;
    esac
    show_cursor
}

send_metrics() {
    local metric=$1
    local value=$2
    local date=$3
    hide_cursor

    local response=$(curl -s -w "%{http_code}" https://$api_key@www.hostedgraphite.com/api/v1/sink --data-binary "test.$hostname.$metric $value $date")
    local http_code=${response: -3} 

    move_cursor $(( initial_rows - 2 )) 0
    if [[ $http_code -ge 200 && $http_code -lt 300 ]]; then
        printf "${GREEN}Metrics are sending successfully.${NC}"
    else
        printf "${RED}Failed to send metrics. HTTP status code: $http_code"
    fi
    printf "${NC}"
}



monitoring_type_prompt() {
    local width=$1
    local height=$2
    local start_row=$3
    local start_col=$4
    local prompt="Please choose the monitoring type:"
    local options=("${monitoring_types[@]}") cur=0 count=${#options[@]} index=0
    local esc=$(printf "\033")

    selected_choice=""
    move_cursor $start_row $start_col
    printf "$prompt\n"

    while true; do
        index=0 
        for o in ${options[@]}; do
            if [ "$index" == "$cur" ]; then
                printf " >\033[7m%s\033[0m\n" "$o"
            else
                printf "  %s\n" "$o"
            fi
            index=$(( index + 1 ))
        done

        read -rsn1 key
        if [[ $key == $esc ]]; then
            read -rsn2 key
            if [[ $key == "[A" ]]; then
                cur=$(( cur - 1 ))
                [ $cur -lt 0 ] && cur=0
            elif [[ $key == "[B" ]]; then
                cur=$(( cur + 1 ))
                [ $cur -ge $count ] && cur=$(( count - 1 ))
            fi
        elif [[ $key == "" ]]; then
            break
        fi
        printf "\033[%sA" "$count"
    done

    selected_choice=${options[$cur]}
    show_cursor
}

loading_bar() {
    local elapsed=$1
    local percent=$2
    local max_bar_length=$3
    hide_cursor
    move_cursor 17 0
    if [ $percent -gt 75 ]; then
        color=$GREEN
    elif [ $percent -gt 50 ]; then
        color=$YELLOW
    else
        color=$RED
    fi

    printf "${color}"
    fill_length=$(( max_bar_length * elapsed / $test_duration ))
    bar=$(printf "%-${max_bar_length}s" "#" | tr ' ' '#' )
    empty=$(printf "%-${max_bar_length}s" "-" | tr ' ' '-')
    printf "\r[${bar:0:$fill_length}${empty:$fill_length:$max_bar_length}] $percent%%"
    printf "${NC}"
}

info_slides() {
    local start_row=$1
    local start_col=$2
    local width=$3
    local height=$4
    local slide_number=$((1 + $RANDOM % 6))

    clear_region $start_row $(( start_row + height )) $start_col $initial_columns

    declare -a slides=(
        [0]="Aggregation Information"
        [1]="Data views information"
        [2]="Data Resolution Information"
        [3]="Data Storage Information"
        [4]="Data Visualization Information"
        [5]="Data Querying Information"
        [6]="Alerting Information"
    )

    declare -a description=(
        [0]="We aggregate data into 3 buckets (30s, 300s, 3600s) resolutions."
        [1]="Generates different statistical views on your data. Append :avg, :sum, :max, :min to your metric (test.<hostname>.cpu.usage:sum). The default is avg."
        [2]="Data display at: 1h-10h 30s, 10h-5d 300s, 5d-2y 3600s resolutions."
        [3]="We store 30s for 3 days, 300s for 6 months, 3600s data for two years."
        [4]="Visualize data in different ways. (Graphs, Bars, Pie Charts, and many more)"
        [5]="Use dot notation to query data. (test.<hostname>.cpu.usage)"
        [6]="Generate Alerts based on your data, send notifications to your team with Slack, Email, Pagerduty, and more."
    )

    move_cursor $start_row $start_col
    printf "${ORANGE}${slides[$slide_number]}${NC}"
    ((start_row++))

    description=${description[$slide_number]}
    adjusted_content $(( width / 2 )) $height $start_row $start_col "$description"
}

reset_data_arr() {
    local data_set_type=$1

    case $data_set_type in
        "cpu")
            cpu_data=()
            ;;
        "ram")
            ram_total=()
            ram_used=()
            ram_available=()
            ;;
        "disk")
            filesystems=()
            sizes=()
            useds=()
            avails=()
            ;;
        *)
            echo "Invalid data set: $data_set"
            exit 1
            ;;
    esac
}


# COLLECTORS
collect_cpu_data() {
    if [[ "$os_name" == "Linux" ]]; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    elif [[ "$os_name" == "Darwin" ]]; then
        cpu_usage=$(top -l 1 -n 0 | awk '/CPU usage/ {print $3}' | sed 's/%//')
    else
        printf "Unsupported OS: %s\n" "$os_name"
        exit 1
    fi

    cpu_data+=( "$cpu_usage" )
}

collect_ram_data() {
    if [[ "$os_name" == "Linux" ]]; then
        free_output=$(free -m)

        mem_total=$(echo "$free_output" | awk '/^Mem:/ {print $2}')
        mem_used=$(echo "$free_output" | awk '/^Mem:/ {print $3}')
        mem_available=$(echo "$free_output" | awk '/^Mem:/ {print $7}')

    elif [[ "$os_name" == "Darwin" ]]; then
        vm_stat_output=$(vm_stat)
        pages_free=$(echo "$vm_stat_output" | awk '/Pages free/ {print $3}')
        pages_active=$(echo "$vm_stat_output" | awk '/Pages active/ {print $3}')
        pages_inactive=$(echo "$vm_stat_output" | awk '/Pages inactive/ {print $3}')
        pages_wired=$(echo "$vm_stat_output" | awk '/Pages wired down/ {print $4}')
        page_size=$(sysctl -n hw.pagesize)

        mem_total=$(echo "scale=2; ($pages_free + $pages_active + $pages_inactive) * $page_size / 1024 / 1024" | bc)
        mem_used=$(echo "scale=2; ($pages_active + $pages_wired) * $page_size / 1024 / 1024" | bc)
        mem_available=$(echo "scale=2; ($pages_free + $pages_inactive) * $page_size / 1024 / 1024" | bc)
    else
        printf "Unsupported OS: $os_name"
        exit 1
    fi

    ram_total+=( "$mem_total" )
    ram_used+=( "$mem_used" )
    ram_available+=( "$mem_available" )
}

collect_disk_space_data() {
    local cmd="$(df | head -n 4 | tail -n +2)"


    while read -r line; do
        num_non_numeric_fields=$(echo "$line" | awk '{
            count = 0;
            for (i = 1; $i !~ /^[0-9]+$/; i++) {
                count++;
            }
            print count;
        }')

        filesystem=$(echo "$line" | awk -v count="$num_non_numeric_fields" '{
            fs = $1;
            for (i = 2; i <= count; i++) {
                fs = fs " " $i;
            }
            gsub(/:\\/, "_drive_", fs);
            gsub(/\\/, "_", fs);
            gsub("/", "_", fs);
            gsub(" ", "_", fs);
            print fs;
        }')

        size=$(echo "$line" | awk -v count="$num_non_numeric_fields" '{print $(count + 1)}')
        used=$(echo "$line" | awk -v count="$num_non_numeric_fields" '{print $(count + 2)}')
        avail=$(echo "$line" | awk -v count="$num_non_numeric_fields" '{print $(count + 3)}')

        filesystems+=( "$filesystem" )
        sizes+=( "$size" )
        useds+=( "$used" )
        avails+=( "$avail" )
    done <<< "$cmd"
}

# Layout for CLI
# HEADER
header() {
    printf "This will test the process of sending and processing ${GREEN}CPU${NC}, ${GREEN}Memory${NC}, ${GREEN}Disk Metrics${NC} to ${ORANGE}HostedGraphite. ${NC}"
    printf "This is only a sample test and will run for ${RED}2 mins.${NC}"
}

api_prompt() {
    local width=$1
    local height=$2
    local start_row=$3
    local start_col=$4

    move_cursor $start_row $start_col
    printf "Please Enter your API key [ENTER]: "
    read api_key
    sleep 2
}

display() {
    local metric_col_start=$1
    local slide_col_start=$2
    local start_row=$3
    local width=$4
    local height=$5
    local date=$(date +%s)

    adjusted_row=$(( start_row + 3 ))
    info_slides $adjusted_row $slide_col_start $width $height
    
    move_cursor $adjusted_row 0
    hide_cursor

    #cpu
    if [ ${#cpu_data[@]} -ne 0 ]; then
        for i in "${!cpu_data[@]}"; do
            printf "CPU Usage: ${YELLOW}${cpu_data[i]}${NC}\n"
            send_metrics "cpu.usage" "${cpu_data[i]}" $date
        done
        ((adjusted_row++))
        reset_data_arr "cpu"
    fi

    #RAM
    if [ ${#ram_total[@]} -ne 0 ]; then
        for i in "${!ram_total[@]}";do
            clear_region $adjusted_row $height 0 $slide_col_start
            move_cursor $adjusted_row 0
            printf "Memory Total: ${YELLOW}${ram_total[i]}${NC}\n"
            ((adjusted_row++))
            printf "Memory Used: ${YELLOW}${ram_used[i]}${NC}\n"
            ((adjusted_row++))
            printf "Memory Available: ${YELLOW}${ram_available[i]}${NC}\n"
            ((adjusted_row++))

            send_metrics "mem.total" "${ram_total[i]}" $date
            send_metrics "mem.used" "${ram_used[i]}" $date
            send_metrics "mem.available" "${ram_available[i]}" $date
        done
        reset_data_arr "ram"
    fi

    #disk space
    if [ ${#filesystems[@]} -ne 0 ];then
        for i in "${!filesystems[@]}"; do
            clear_region $adjusted_row $(( height + $adjusted_row - 8 )) 0 $(( slide_col_start - 1 ))
            move_cursor $adjusted_row 0

            printf "Disk Space Size: ${YELLOW}${filesystems[i]} - ${GREEN}${sizes[i]}${NC}\n"
            printf "Disk Space Used: ${YELLOW}${filesystems[i]} - ${GREEN}${useds[i]}${NC}\n"
            printf "Disk Space Available: ${YELLOW}${filesystems[i]} - ${GREEN}${avails[i]}${NC}\n"

            send_metrics "${filesystems[i]}.size" "${sizes[i]}" $date
            send_metrics "${filesystems[i]}.used" "${useds[i]}" $date
            send_metrics "${filesystems[i]}.avail" "${avails[i]}" $date
            sleep 1
        done
        reset_data_arr "disk"
    fi
}

content_body() {
    local width=$1
    local height=$2
    local start_row=$3
    local start_col=$4

    local metric_col_start=start_col
    local slide_col_start=$((width / 2))

    local max_bar_length=$(( width * 80 / 100 ))
    local end=$(( SECONDS + $test_duration ))

    while [ $SECONDS -lt $end ]; do
        elapsed=$(( SECONDS - (end - $test_duration) ))
        percent=$(( elapsed * 100 / $test_duration ))
        loading_bar $elapsed $percent $max_bar_length

        case $selected_choice in
            "CPU")
                collect_cpu_data
                ;;
            "DISK")
                collect_disk_space_data
                ;;
            "RAM")
                collect_ram_data
                ;;
            "ALL")
                collect_cpu_data
                collect_ram_data
                collect_disk_space_data
                ;;
        esac
        display $metric_col_start $slide_col_start $start_row $width $height
        sleep 1
    done
    loading_bar $test_duration 100 $max_bar_length
    show_cursor
}

footer() {
    move_cursor $(( $initial_rows - 3 )) 0
    printf "${GREEN}You have reached the end of the test.\n"
    printf "To view your metric, you can visit: https://www.hostedgraphite.com/app/metrics/ \n"
    printf "Goodbye!\n"
}

adjusted_content() {
    local width=$1
    local height=$2
    local start_row=$3
    local start_col=$4
    shift 4
    local content=("$@")
    local current_length=0

    width=$(( width - 10 ))

    move_cursor $start_row $start_col

    for word in ${content[@]}; do
        current_length=$((current_length + ${#word}))
        if [ $current_length -gt $width ]; then
            ((start_row++))
            move_cursor $start_row $start_col
            current_length=${#word}
        fi
        printf "$word "
    done
}

container() {
    local box_name=$1

    case $box_name in
        "logo")
            width=72
            height=15
            center=$(( initial_columns / 2 ))
            middle_container=$(( width / 2 ))
            start_row=1
            start_col=$(( center - middle_container ))
            col_offset=$(( center - middle_container ))
            display_ascii_art $start_row $start_col "flame" flame
            display_ascii_art $(( start_row + 5 )) $(( center - 16 )) "mf" mf
            ;;
        "header")
            width=$initial_columns
            height=3
            start_row=14
            start_col=0
            adjusted_content $width $height $start_row $start_col "$(header)"
            ;;
        "api_prompt")
            width=$initial_columns
            height=4
            start_row=16
            start_col=0
            api_prompt $width $height $start_row $start_col
            ;;
        "type_prompt")
            width=$initial_columns
            height=5
            start_row=16
            start_col=0
            monitoring_type_prompt $width $height $start_row $start_col
            ;;
        "content_body")
            width=$initial_columns
            height=10
            start_row=16
            start_col=0
            content_body $width $height $start_row $start_col
    esac
}

resize_components() {
    sleep 1
    terminal_size=$(stty size)
    initial_rows=$(echo $terminal_size | cut -d ' ' -f 1)
    initial_columns=$(echo $terminal_size | cut -d ' ' -f 2)

    clear
    if [ "$LOGO_VISIBLE" = true ]; then
        container "logo"
    fi
    
    if [ "$HEADER_VISIBLE" = true ]; then
        container "header"
    fi

    if [ "$API_PROMPT_VISIBLE" = true ]; then
        container "api_prompt"
    fi

    if [ "$MONITORING_TYPE_VISIBLE" = true ]; then
        container "type_prompt"
    fi

}

main() {
    clear

    LOGO_VISIBLE=true
    container "logo"
    HEADER_VISIBLE=true
    container "header"
    sleep 1
    API_PROMPT_VISIBLE=true
    container "api_prompt"
    API_PROMPT_VISIBLE=false
    clear_region 16 18 0 $initial_columns
    sleep 1
    container "type_prompt"
    sleep 1
    clear_region 16 $initial_rows 0 $initial_columns
    container "content_body"
    footer
    show_cursor
}

trap handle_interruption SIGINT
trap 'resize_components' SIGWINCH
main
