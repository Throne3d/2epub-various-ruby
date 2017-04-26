ls | grep -v default.log | grep output_report | sort | tail -n 1 | xargs -d "\n" cat

