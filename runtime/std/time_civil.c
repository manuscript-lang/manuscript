/* Calendar arithmetic for the @std/time natives: days since 1970-01-01 and civil dates, converted with Howard
 * Hinnant's era algorithms. The Gregorian rules are proleptic, so year 1 and year 9999 follow the same rules as now. */
#include "time_internal.h"

enum {
    DAYS_PER_ERA = 146097, /* 400 years */
    DAYS_FROM_YEAR_0000_TO_1970 = 719468,
    THURSDAY = 4, /* 1970-01-01 */
};

static int64_t floor_div(int64_t a, int64_t b) {
    const int64_t quotient = a / b;
    return (a % b != 0 && (a < 0) != (b < 0)) ? quotient - 1 : quotient;
}

static int64_t floor_mod(int64_t a, int64_t b) { return a - floor_div(a, b) * b; }

static bool is_leap(int64_t year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }

int64_t ms_days_in_month(int64_t year, int64_t month) {
    switch (month) {
    case 2:
        return is_leap(year) ? 29 : 28;
    case 4:
    case 6:
    case 9:
    case 11:
        return 30;
    default:
        return 31;
    }
}

/* Days since 1970-01-01 of a civil date (month 1..12). */
static int64_t days_from_civil(int64_t year, int64_t month, int64_t day) {
    const int64_t y = month <= 2 ? year - 1 : year;
    const int64_t era = floor_div(y, 400);
    const int64_t year_of_era = y - era * 400;
    const int64_t month_from_march = (month + 9) % 12;
    const int64_t day_of_year = (153 * month_from_march + 2) / 5 + day - 1;
    const int64_t day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    return era * DAYS_PER_ERA + day_of_era - DAYS_FROM_YEAR_0000_TO_1970;
}

typedef struct CivilDate {
    int64_t year, month, day;
} CivilDate;

static CivilDate civil_from_days(int64_t days) {
    const int64_t z = days + DAYS_FROM_YEAR_0000_TO_1970;
    const int64_t era = floor_div(z, DAYS_PER_ERA);
    const int64_t day_of_era = z - era * DAYS_PER_ERA;
    const int64_t year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    const int64_t day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    const int64_t month_from_march = (5 * day_of_year + 2) / 153;
    const int64_t month = month_from_march < 10 ? month_from_march + 3 : month_from_march - 9;
    return (CivilDate){
        .year = year_of_era + era * 400 + (month <= 2 ? 1 : 0),
        .month = month,
        .day = day_of_year - (153 * month_from_march + 2) / 5 + 1,
    };
}

MsCivil ms_civil_of(int64_t local_seconds, int64_t nanosecond) {
    const int64_t days = floor_div(local_seconds, MS_SECONDS_PER_DAY);
    const int64_t rest = floor_mod(local_seconds, MS_SECONDS_PER_DAY);
    const CivilDate date = civil_from_days(days);
    return (MsCivil){
        .year = date.year,
        .month = date.month,
        .day = date.day,
        .hour = rest / 3600,
        .minute = rest % 3600 / 60,
        .second = rest % 60,
        .nanosecond = nanosecond,
        .weekday = floor_mod(days + THURSDAY, 7),
        .day_of_year = days - days_from_civil(date.year, 1, 1) + 1,
    };
}

int64_t ms_local_seconds(int64_t year, int64_t month, int64_t day, int64_t hour, int64_t minute, int64_t second) {
    return days_from_civil(year, month, day) * MS_SECONDS_PER_DAY + hour * 3600 + minute * 60 + second;
}
