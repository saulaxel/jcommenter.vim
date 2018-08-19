# Jcommenter

A [neo]vim plugin to generate JavaDoc.

This is a mirror of http://www.vim.org/scripts/script.php?script_id=20

Updated 19.08.2018 KB

## Description:

Generates JavaDoc (and some other) comments for java-sources. This is triggered by executing the JCommentWriter()-function while the cursor is over something meaningfull, or if a selection exists, the selected text is parsed and the comment template is generated based on that.

The following comments are generated (in the appropriate situations):
1. File comments: user specifies the template, generated when the cursor is on the first line of the file.
1. Class comments: generated when on top of a class declaration.
1. Method comments: generated when on top of a metod declaration. @return, @params, and @throws are generated, if applicable. If executed on a method declaration which already has JavaDoc-comments, updates the javadoc-comments by removing/adding tags as needed.
1.  Field comments. Simply adds an empty JavaDoc-comment template above the field declaration
1. Copy @<name> -tags. When executed on @something, creates a tag with the same name directly above the line the cursor is currently on.
1. @throws for RuntimeExceptions. When executed on a line containing something like "throw new RuntimeException()", a @throws-tag is added to the previous JavaDoc-comment.
1. Block-end comments. When executed on a line containing a '}'-character and possibly some whitespace (but nothing else), generates a one-line-comment describing what block the '}' is terminating. For example, the comment for "aVeryLongMethod" is  "// END: aVeryLongMethod".

There are a bunch of other functions to support the comment generation. The style of the comment templates is configurable

## Installation

Use your favorite plugin manager and add a line as the later to the corresponding part of your vim configuration:

        <Name-of-plugin-manager> 'saulaxel/jcommenter.vim'
