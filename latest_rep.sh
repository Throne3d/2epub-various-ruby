cd logs && ls | grep -v default.log | grep output_report | sort | tail -n 1 | xargs -d "\n" cat | xclip -sel clip
xclip -o -sel clip

