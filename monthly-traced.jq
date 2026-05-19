def last_day_of_month:
  split("-") | (.[0] | tonumber) as $y | (.[1] | tonumber) as $m |
  (if $m == 2 then
    if ($y % 4 == 0 and ($y % 100 != 0 or $y % 400 == 0)) then 29 else 28 end
  elif ($m == 4 or $m == 6 or $m == 9 or $m == 11) then 30
  else 31 end) |
  tostring | if length == 1 then "0" + . else . end;

(.[0] | {schema_version, institution, account}) as $meta |

([.[].statements[].transactions[]] | sort_by(.posted_date)) as $all_txns |
([.[].statements[].daily_balances[]] | unique_by(.date) | sort_by(.date)) as $all_daily |

([.[].statements[] | {date: .period.start, amount: .balances.opening.amount, bal_date: .balances.opening.date}]
  | sort_by(.date) | .[0]) as $earliest_opening |

([$all_txns[].posted_date[:7], $all_daily[].date[:7]] | unique | sort) as $months |

$months[] as $month |

([$all_txns[] | select(.posted_date[:7] == $month)]) as $txns |
([$all_daily[] | select(.date[:7] == $month)]) as $daily |

([$all_daily[] | select(.date < "\($month)-01")] | last // null) as $prior |
(if $prior then {amount: $prior.balance, date: $prior.date}
 elif $month == $months[0] then {amount: $earliest_opening.amount, date: $earliest_opening.bal_date}
 else null end) as $opening |

($daily | last // null) as $last |
(if $last then {amount: $last.balance, date: $last.date} else null end) as $closing |

([$txns[] | select(.amount > 0)]) as $deps |
([$txns[] | select(.amount < 0)]) as $wds |

{
  filename: "\($month).json",
  filedata: ($meta + {
    statements: [{
      id: "stmt_\($month)",
      period: {
        start: "\($month)-01",
        end: "\($month)-\($month | last_day_of_month)"
      },
      balances: {
        opening: $opening,
        closing: $closing
      },
      totals: {
        deposits: {
          count: ($deps | length),
          amount: ([$deps[].amount] | add // 0 | . * 100 | round / 100)
        },
        withdrawals: {
          count: ($wds | length),
          amount: ([$wds[].amount] | map(fabs) | add // 0 | . * 100 | round / 100)
        }
      },
      daily_balances: $daily,
      transactions: $txns
    }]
  })
}
