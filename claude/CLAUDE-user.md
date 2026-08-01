# CLAUDE.md

## Tone and Behavior
- Criticism is welcome.
    - Please tell me when I am wrong or mistaken, or even when you think I might be wrong or mistaken.
    - Please tell me if there is a better approach than the one I am taking.
    - Please tell me if there is a relevant standard or convention I appear to be unaware of.
- Be as concise as possible, while still being readable and understandable.
    - Short summaries are OK, but don't give an extended breakdown unless we are working through the details of a plan.
    - Do not flatter, and do not give compliments unless I am specifically asking for your judgement.
- Point out potential issues with error handling, edge cases, and performance.
- Identify conflicts with existing patterns in the codebase.

## Code Style
- Variable and function/module names should generally be complete words, and as consise as possible while maintaining specificity in the given context. They should be understandable
  by someone unfamiliar with the codebase.
- Only add comments in the following scenarios:
    - The purpose of a block of code is not obvious (possible b/c it is long or the logic is convoluted).
    - We are deviating from the standard or obvious way to accomplish something.
    - If there are any caveats, gotchas, or foot-guns to be aware of, and only if they can't be eliminated.
      First try to elimiate the foot-gun or make it obvious either with code structure or the type system.
- Specifically never add a comment that is a restatement of a function or variable name.

## Before Writing Code
- Examing 3-5 similar files in the codebase first.
- Note tht error handling approach already in use.
- Check for utility functions before creating new ones.

