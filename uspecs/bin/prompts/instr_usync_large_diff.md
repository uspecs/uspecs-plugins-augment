# Large diff gate

## data

Inform the user that there are a lot of changes since the baseline (${size} bytes) and it may take a while and consume significant tokens/cost. Ask whether to proceed:

1. Yes
2. Cancel

On "Yes", rerun: `bash ${softeng_sh} action usync -y`

Format size in human-readable form for better user experience.
