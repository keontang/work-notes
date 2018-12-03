**Block styles with block chomping indicator (>-, |-, >+, |+)**

You can control the handling of the final new line in the string, and any trailing blank lines (\n\n) by adding a block chomping indicator character:

>, |: "clip": keep the line feed, remove the trailing blank lines.
>-, |-: "strip": remove the line feed, remove the trailing blank lines.
>+, |+: "keep": keep the line feed, keep trailing blank lines.
