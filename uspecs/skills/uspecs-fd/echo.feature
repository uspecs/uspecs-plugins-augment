Feature: Print text with echo
  User runs echo command to print text to stdout

  Rule: Core behavior

    Scenario Outline: Print arguments
      When User runs `echo <args>`
      Then stdout is <output>
      And exit code is 0
      Examples:
        | args                      | output                               |
        | hello                     | "hello{NEWLINE}"                     |
        | hello world               | "hello world{NEWLINE}"               |
        | no\t\n escapes by default | "no\t\n escapes by default{NEWLINE}" |
        |                           | "{NEWLINE}"                          |

    Scenario: Variable expansion
      Given environment variables:
        | name | value       |
        | USER | alice       |
        | HOME | /home/alice |
      When User runs `echo $USER at $HOME`
      Then stdout is "alice at /home/alice{NEWLINE}"

  Rule: Options

    Scenario: -n suppresses the trailing newline
      When User runs `echo -n hello`
      Then stdout is "hello"

    # Recognized escape sequences are listed in [echo--reqs.md](./echo--reqs.md)
    Scenario Outline: -e enables backslash escapes
      When User runs `echo -e <args>`
      Then stdout is <output>
      Examples:
        | args           | output                         |
        | "a\tb"         | "a{TAB}b{NEWLINE}"             |
        | "line1\nline2" | "line1{NEWLINE}line2{NEWLINE}" |

  Rule: Edge cases

    Scenario: Unknown option is treated as literal text
      When User runs `echo --unknown`
      Then stdout is "--unknown{NEWLINE}"
      And exit code is 0