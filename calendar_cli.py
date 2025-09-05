import sys
import calendar


def main():
    if len(sys.argv) != 3:
        print("Usage: python calendar_cli.py <year> <month>")
        return
    try:
        year = int(sys.argv[1])
        month = int(sys.argv[2])
    except ValueError:
        print("Year and month must be integers")
        return
    if month < 1 or month > 12:
        print("Month must be between 1 and 12")
        return
    cal = calendar.TextCalendar(calendar.SUNDAY)
    print(cal.formatmonth(year, month))

if __name__ == "__main__":
    main()
