# Requirements: Print text with echo

## Recognized backslash escape sequences (with -e)

| sequence | output                                 |
|----------|----------------------------------------|
| \a       | alert (BEL)                            |
| \b       | backspace                              |
| \c       | suppress further output                |
| \e       | escape                                 |
| \f       | form feed                              |
| \n       | newline                                |
| \r       | carriage return                        |
| \t       | horizontal tab                         |
| \v       | vertical tab                           |
| \\       | single backslash                       |
| \0NNN    | byte with octal value NNN (1-3 digits) |
| \xHH     | byte with hex value HH (1-2 digits)    |

Rules:

- Unknown escape sequences: printed literally, including the leading backslash
- Without `-e`: all backslash sequences are printed literally
