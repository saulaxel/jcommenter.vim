" File:          jcommenter.vim
" Summary:       Functions for documenting java-code
" Author:        Kalle Björklid <bjorklid@st.jyu.fi>
" Last Modified: 12.08.2018
" Version:       1.3.2
" Tested on gvim 6.0 on Win32

" TODO: search for function etc not commented
" TODO: support for the umlaut-chars etc. that can be also used in java
" TODO: Inner classes/interfaces...
" TODO: sort exceptions alphabetically (see
"       http://java.sun.com/j2se/javadoc/writingdoccomments/index.html)
" TODO: comment the script
"
"=====================================================================

scriptencoding utf-8
if exists('s:javacomplete_loaded') || &compatible
  finish
endif
let s:javacomplete_loaded = 1

" ===================================================
" Default configuration
" ===================================================
function! s:SetDefaultVal(var, val)
    if (!exists(a:var))
        execute 'let ' . a:var . ' = ' . string(a:val)
    endif
endfunction

" The initial settings correspond with Sun's coding conventions.
call s:SetDefaultVal('g:jcommenter_default_mappings', v:true)
call s:SetDefaultVal('g:jcommenter_move_cursor', v:true)
call s:SetDefaultVal('g:jcommenter_description_starts_from_first_line', v:false)
call s:SetDefaultVal('g:jcommenter_autostart_insert_mode', v:true)
call s:SetDefaultVal('g:jcommenter_method_description_space', 2)
call s:SetDefaultVal('g:jcommenter_field_description_space', 1)
call s:SetDefaultVal('g:jcommenter_class_description_space', 2)
call s:SetDefaultVal('g:jcommenter_smart_method_description_spacing', v:true)
call s:SetDefaultVal('g:jcommenter_class_author', '')
call s:SetDefaultVal('g:jcommenter_class_version', '')
call s:SetDefaultVal('g:jcommenter_file_author', '')
call s:SetDefaultVal('g:jcommenter_file_copyright', '')
call s:SetDefaultVal('g:jcommenter_use_exception_tag', 0)
call s:SetDefaultVal('g:jcommenter_file_noautotime', v:false)
call s:SetDefaultVal('g:jcommenter_update_comments', v:true)
call s:SetDefaultVal('g:jcommenter_remove_tags_on_update', v:true)
call s:SetDefaultVal('g:jcommenter_add_empty_line', v:true)
call s:SetDefaultVal('g:jcommenter_modeline', '// vim'
      \. ': ' . (&expandtab ? 'et' : 'noet') . 'sw=' . &shiftwidth . ' ts=' . &tabstop)
" Unsupported feature:
" If you want to put some text where the parameter text, return text etc. would
" normally go, uncomment and add the wanted text to these variables (this feature
" is considered "unsupported", which means it will not work perfectly with every
" other aspect of this script. For example, this will break the logic used to
" find "invalid" comments):
call s:SetDefaultVal('g:jcommenter_default_param_text', '')
call s:SetDefaultVal('g:jcommenter_default_return_text', '')
call s:SetDefaultVal('g:jcommenter_default_throw_text', '')
" Another "unsupported" feature: define the number of lines added after each
" "tag-group" (except exceptions, which is often the last group). does not work
" well with comment updating currently:
call s:SetDefaultVal('g:jcommenter_tag_space', 0)
call s:SetDefaultVal('g:jcommenter_file_template_function', '')

" ===================================================
" Default mappings
" ===================================================
if g:jcommenter_default_mappings
  map  <M-c>      :call JCommentWriter()<CR>
  imap <M-c> <esc>:call JCommentWriter()<CR>

  map  <M-n>      :call SearchInvalidComment(0)<CR>
  imap <M-n> <esc>:call SearchInvalidComment(0)<CR>a
  map  <M-p>      :call SearchInvalidComment(1)<CR>
  imap <M-p> <esc>:call SearchInvalidComment(1)<CR>a

" TODO: test this map
  iabbrev {- {<esc>:call search('\w', 'b')<CR>:call ConditionalWriter()<CR>0:call search('{')<CR>a

  iabbrev }- }<esc>h%?\w<CR>:nohl<CR>:call JCommentWriter()<CR>
endif

" ===================================================
" Script local variables
" ===================================================
" Text to write before the string when using the AppendStr-function.
let s:indent = ''

" String with the text of the commenter was walled over
let s:combinedString = ''

let s:rangeStart = 1   " line on which the range started
let s:rangeEnd   = 1   " line on which the range ended

let s:docCommentStart = -1
let s:docCommentEnd   = -1

let s:debugstring = ''

" ===================================================
" Public function that exposes the functionality
" ===================================================
function! JCommentWriter() range
  let s:rangeStart     = a:firstline
  let s:rangeEnd       = a:lastline
  let s:combinedString = s:GetCombinedString(s:rangeStart, s:rangeEnd)

  let s:debugstring = ''

  if s:IsFileComments()
    call s:WriteFileComments()
  elseif s:IsModeLine()
    call s:WriteModeLine()
  elseif s:IsFunctionEnd()
    call s:WriteFunctionEndComments()
  elseif s:IsExceptionDeclaration()
    call s:WriteFoundException()
  elseif s:IsMethod()
    let s:debugstring .= 'isMethod '
    let l:method_comment_update_only = s:WriteMethodComments()
    if !l:method_comment_update_only
      call s:AddEmpty()
    endif
  elseif s:IsClass()
    call s:WriteClassComments()
    call s:AddEmpty()
  elseif s:IsSinglelineComment()
    call s:ExpandSinglelineComments(s:rangeStart)
  elseif s:IsCommentTag()
    call s:WriteCopyOfTag()
  elseif s:IsVariable()
    call s:WriteFieldComments()
    call s:AddEmpty()
  else
    call s:Message('Nothing to do')
  endif

  " echo s:debugstring
endfunction

" ===================================================
" The update functions for method comments
" ===================================================

function! s:UpdateAllTags()
  let s:indent = s:GetIndentation(s:combinedString)
  call s:UpdateParameters()
  call s:UpdateReturnValue()
  call s:UpdateExceptions()
endfunction

function! s:UpdateExceptions()
  let l:exceptionName = s:GetNextThrowName()
  let l:seeTagPos = s:FindTag(s:docCommentStart, s:docCommentEnd, 'see', '')
  if l:seeTagPos > -1
    let l:tagAppendPos = l:seeTagPos - 1
  else
    let l:tagAppendPos = s:docCommentEnd - 1
  endif
  while l:exceptionName !=# ''
    let l:tagPos = s:FindTag(s:docCommentStart, s:docCommentEnd, 'throws', l:exceptionName)
    if l:tagPos < 0
      let l:tagPos = s:FindTag(s:docCommentStart, s:docCommentEnd, 'exception', l:exceptionName)
    endif
    if l:tagPos > -1
      let l:tagAppendPos = l:tagPos
      let l:exceptionName = s:GetNextThrowName()
      continue
    endif
    let s:appendPos = l:tagAppendPos
    call s:AppendStr(' * @throws ' . l:exceptionName . ' ' . g:jcommenter_default_throw_text)
    call s:MarkUpdateMade(l:tagAppendPos + 1)
    let s:docCommentEnd += 1
    let l:tagAppendPos += 1
    let l:tagName = s:GetNextParameterName()
  endwhile
endfunction

function! s:UpdateReturnValue()
  if s:method_returnValue ==# ''
    if g:jcommenter_remove_tags_on_update
      call s:RemoveTag(s:docCommentStart, s:docCommentEnd, 'return', '')
    endif
    return
  endif
  let l:returnTagPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'return')
  if l:returnTagPos > -1 && s:method_returnValue !=# ''
    return
  endif
  let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'throws') - 1
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'exception') - 1
  endif
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'see') - 1
  endif
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:docCommentEnd - 1
  endif
  let s:appendPos = l:tagAppendPos
  call s:AppendStr(' * @return ' . g:jcommenter_default_return_text)
  call s:MarkUpdateMade(l:tagAppendPos + 1)
  let s:docCommentEnd += 1
endfunction

function! s:RemoveNonExistingParameters()
  call s:ResolveMethodParams(s:combinedString)
  let l:paramlist = s:method_paramList
  let l:pos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'param')
  let l:Start = l:pos

  while l:pos > 0
    let l:line = getline(l:pos)
    let l:tagParam = substitute(l:line, '^\s*\(\*\s*\)\=@[a-zA-Z]*\s\+\(\S*\).*', '\2', '')

    let l:paramExists = 0
    let l:existingParam = s:GetNextParameterName()
    while l:existingParam !=# ''

      if l:existingParam == l:tagParam
        let l:paramExists = 1
        break
      endif
      let l:existingParam = s:GetNextParameterName()
    endwhile
    if l:paramExists == 0
      call s:RemoveTag(l:Start, s:docCommentEnd, 'param', l:tagParam)
    else
      let l:Start += 1
    endif

    let s:method_paramList = l:paramlist
    let l:pos = s:FindFirstTag(l:Start, s:docCommentEnd, 'param')
  endwhile
endfunction

function! s:UpdateParameters()
  let l:tagName = s:GetNextParameterName()

  "Try to find out where the tags that might be added should be written.
  let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'param') - 1
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'return') - 1
  endif
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'throws') - 1
  endif
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'exception') - 1
  endif
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:FindFirstTag(s:docCommentStart, s:docCommentEnd, 'see') - 1
  endif
  if l:tagAppendPos < 0
    let l:tagAppendPos = s:docCommentEnd - 1
  endif

  while l:tagName !=# ''
    let l:tagPos = s:FindTag(s:docCommentStart, s:docCommentEnd, 'param', l:tagName)
    if l:tagPos > -1
      let l:tagAppendPos = l:tagPos
      let l:tagName = s:GetNextParameterName()
      continue
    endif
    let s:appendPos = l:tagAppendPos
    call s:AppendStr(' * @param ' . l:tagName . ' ' . g:jcommenter_default_param_text)
    call s:MarkUpdateMade(l:tagAppendPos + 1)
    let s:docCommentEnd += 1
    let l:tagAppendPos += 1
    let l:tagName = s:GetNextParameterName()
  endwhile

  if g:jcommenter_remove_tags_on_update
    call s:RemoveNonExistingParameters()
  endif
endfunction

function! s:FindTag(rangeStart, rangeEnd, tagName, tagParam)
  let l:i = a:rangeStart
  while l:i <= a:rangeEnd
    if a:tagParam !=# ''
      if getline(l:i) =~# '^\s*\%(\*\s*\)\=@' . a:tagName . '\s\+' . a:tagParam . '\%(\s\|$\)'
        return l:i
      endif
    else
      if getline(l:i) =~# '^\s*\%(\*\s*\)\=@' . a:tagName . '\%(\s\|$\)'
        return l:i
      endif
    endif
    let l:i = 1
  endwhile
  return -1
endfunction

function! s:FindFirstTag(rangeStart, rangeEnd, tagName)
  let l:i = a:rangeStart
  while l:i <= a:rangeEnd
    if getline(l:i) =~# '^\s*\%(\*\s*\)\=@' . a:tagName . '\%(\s\|$\)'
      return l:i
    endif
    let l:i += 1
  endwhile
  return -1
endfunction

function! s:FindAnyTag(rangeStart, rangeEnd)
  let l:i = a:rangeStart
  while l:i <= a:rangeEnd
    if getline(l:i) =~# '^\s*\%(\*\s*\)\=@'
      return l:i
    endif
    let l:i = 1
  endwhile
  return -1
endfunction

function! s:RemoveTag(rangeStart, rangeEnd, tagName, tagParam)
  let l:tagStartPos = s:FindTag(a:rangeStart, a:rangeEnd, a:tagName, a:tagParam)
  if l:tagStartPos == -1
    return 0
  endif
  let l:tagEndPos = s:FindAnyTag(l:tagStartPos + 1, a:rangeEnd)
  if l:tagEndPos == -1
    let l:tagEndPos = s:docCommentEnd - 1
  endif
  let l:linesToDelete = l:tagEndPos - l:tagStartPos
  execute 'normal! ' . l:tagStartPos . 'G' . l:linesToDelete . 'dd'
  let s:docCommentEnd -= l:linesToDelete
endfunction

function! s:MarkUpdateMade(linenum)
  if s:firstUpdatedTagLine == -1 || a:linenum < s:firstUpdatedTagLine
    let s:firstUpdatedTagLine = a:linenum
  endif
endfunction

" ===================================================
" From single line to multi line
" ===================================================

function! s:ExpandSinglelineCommentsEx(line, space)
  let l:str = getline(a:line)
  let l:singleLinePattern = '^\s*/\*\*\s*\(.*\)\*/\s*$'
  if l:str !~# l:singleLinePattern
    return
  endif
  let s:indent = s:GetIndentation(l:str)
  let l:str = substitute(l:str, l:singleLinePattern, '\1', '')
  execute 'normal! ' . a:line . 'Gdd'
  let s:appendPos = a:line - 1
  call s:AppendStr('/**')
  call s:AppendStr(' * ' . l:str)
  let l:i = 0
  while a:space > l:i
    call s:AppendStr(' * ')
    let l:i = 1
  endwhile
  call s:AppendStr(' */')
  let s:docCommentStart = a:line
  let s:docCommentEnd   = a:line + 2 + a:space
endfunction

function! s:ExpandSinglelineComments(line)
  call s:ExpandSinglelineCommentsEx(a:line, 0)
endfunction

" ===================================================
" Functions for writing the comments
" ===================================================

function! s:WriteMethodComments()
  call s:ResolveMethodParams(s:combinedString)
  let s:appendPos = s:rangeStart - 1
  let s:indent = s:method_indent

  let l:existingDocCommentType = s:HasDocComments()
  let l:method_comment_update_only = 0

  if l:existingDocCommentType && g:jcommenter_update_comments
    let l:method_comment_update_only = 1
    if l:existingDocCommentType == 1
      call s:ExpandSinglelineCommentsEx(s:singleLineCommentPos, 1)
    endif
    let s:firstUpdatedTagLine = -1
    call s:UpdateAllTags()
    if g:jcommenter_move_cursor && s:firstUpdatedTagLine != -1
      call cursor(s:firstUpdatedTagLine, 99999)
      if g:jcommenter_autostart_insert_mode
        startinsert!
      endif
    endif
    return
  endif

  let l:descriptionSpace = g:jcommenter_method_description_space

  call s:AppendStr('/** ')

  let l:param = s:GetNextParameterName()
  let l:exception = s:GetNextThrowName()

  if l:param ==# '' && s:method_returnValue ==# '' && l:exception ==# '' && g:jcommenter_smart_method_description_spacing
    call s:AppendStars(1)
  else
    call s:AppendStars(l:descriptionSpace)
  endif

  let l:hadParam = (l:param !=# '')

  while l:param !=# ''
    call s:AppendStr(' * @param ' . l:param . ' ' . g:jcommenter_default_return_text)
    let l:param = s:GetNextParameterName()
  endwhile

  if g:jcommenter_tag_space && l:hadParam
    call s:AppendStars(g:jcommenter_tag_space)
  endif

  let l:hadReturn = (s:method_returnValue !=# '')

  if s:method_returnValue !=# ''
    call s:AppendStr(' * @return ' . g:jcommenter_default_return_text)
    let s:debugstring .= 'wroteReturnTag '
  endif

  if g:jcommenter_tag_space && l:hadReturn
    call s:AppendStars(g:jcommenter_tag_space)
  endif

  if g:jcommenter_use_exception_tag
    let l:exTag = '@exception '
  else
    let l:exTag = '@throws '
  endif

  "  let hadException = (exception != '')

  while l:exception !=# ''
    call s:AppendStr(' * ' . l:exTag . l:exception . ' ' . g:jcommenter_default_return_text)
    let l:exception = s:GetNextThrowName()
  endwhile

  call s:AppendStr(' */')

  call s:MoveCursor()
endfunction

function! s:WriteFunctionEndComments()
  normal! 0
  if (getline('.')[0] !=# '}')
    call search('}') " won't work if the '}' is the first char (thus the 'if')
  endif
  normal! %
  " Now we are on the '{' mark. Next we go backwards to the line on which the
  " class/method declaration seems to be on:
  call search('\%(^\|.*\s\)\%(\%(\%(\h\w*\)\s*(\)\|\%(\%(class\|interface\)\s\+\%(\u\w*\)\)\).*', 'b')
  let l:header = getline('.')
  let l:name = substitute(l:header, '\%(^\|.*\s\)\%(\%(\(\h\w*\)\s*(\)\|\%(\%(class\|interface\)\s\+\(\u\w*\)\)\).*', '\1\2', '')
  call search('{') " go back to the end...
  normal! %
  execute 'normal! a // END: ' . l:name
endfunction

function! s:WriteFoundException()
  let l:exceptionName = substitute(s:combinedString, '.*\<throw\s*new\s*\([a-zA-Z0-9]*\).*', '\1', '')
  call s:SearchPrevDocComments()
  if s:docCommentEnd == -1
    call s:Message("Found exception declaration, but there's no javadoc comments")
    return
  endif
  let s:appendPos = s:FindTag(s:docCommentStart, s:docCommentEnd, 'throws', '')
  if s:appendPos == -1
    let s:appendPos = s:FindTag(s:docCommentStart, s:docCommentEnd, 'exception', '')
  endif
  if s:appendPos == -1
    let s:appendPos = s:docCommentEnd - 1
  endif
  let s:indent = s:GetIndentation(getline(s:appendPos))
  call s:AppendStr('* ' . '@throws ' . l:exceptionName . ' ' . g:jcommenter_default_throw_text)
  let l:oldStart = s:rangeStart
  let s:rangeStart = s:appendPos - 1
  call s:MoveCursor()
  let s:rangeStart = l:oldStart
endfunction

function! s:WriteCopyOfTag()
  let l:tagName = substitute(s:combinedString, '.*\*\(\s*@\S\+\).*', '\1', '')
  let s:indent = s:GetIndentation(s:combinedString)
  let s:appendPos = s:rangeStart
  call s:AppendStr('*' . l:tagName . ' ')
  call s:MoveCursor()
endfunction

function! s:WriteModeLine()
  let s:appendPos = s:rangeStart
  let s:indent    = ''
  if !empty(g:jcommenter_modeline)
    call s:AppendStr(g:jcommenter_modeline)
  endif
endfunction

function! s:WriteFileComments()
  let s:appendPos = s:rangeStart - 1
  let s:indent    = ''
  let l:author = ''

  if !empty(g:jcommenter_file_template_function) && exists('*' . g:jcommenter_file_template_function)
    let l:TemplateFunction = function(g:jcommenter_file_template_function)
    for l:line in l:TemplateFunction()
      call s:AppendStr(l:line)
    endfor
    return
  endif

  if type(g:jcommenter_file_author) == type('')
    let l:author = g:jcommenter_file_author
  endif

  if g:jcommenter_file_noautotime
    let l:created = ''
  else
    let l:created = strftime('%c')
  endif

  call s:AppendStr('/* file name  : ' . bufname('%'))
  if type(g:jcommenter_file_author) == type('')
    call s:AppendStr(' * authors    : ' . l:author)
  endif
  call s:AppendStr(' * created    : ' . l:created)
  if type(g:jcommenter_file_copyright) == type('')
    call s:AppendStr(' * copyright  : ' . g:jcommenter_file_copyright)
  endif
  call s:AppendStr(' *')
  call s:AppendStr(' * modifications:')
  call s:AppendStr(' *')
  call s:AppendStr(' */')
endfunction

function! s:WriteFieldComments()
  let s:appendPos = s:rangeStart - 1
  let s:indent    = s:GetIndentation(s:combinedString)

  let l:descriptionSpace = g:jcommenter_field_description_space

  if l:descriptionSpace == -1
    call s:AppendStr('/**  */')
    if g:jcommenter_move_cursor
      normal! k$hh
      if g:jcommenter_autostart_insert_mode
        startinsert
      endif
    endif
  else
    call s:AppendStr('/**')
    call s:AppendStars(l:descriptionSpace)
    call s:AppendStr(' */')
    call s:MoveCursor()
  endif

endfunction

function! s:WriteClassComments()
  let s:indent = s:GetIndentation(s:combinedString)

  let l:descriptionSpace = g:jcommenter_class_description_space

  let s:appendPos = s:rangeStart - 1

  call s:AppendStr('/**')

  call s:AppendStars(l:descriptionSpace)

  if type(g:jcommenter_class_author) == type('')
    call s:AppendStr(' * @author ' . g:jcommenter_class_author)
  endif

  if type(g:jcommenter_class_version) == type('')
    call s:AppendStr(' * @version ' . g:jcommenter_class_version)
  endif

  call s:AppendStr(' */')
  call s:MoveCursor()
endfunction

function! Test()
  call s:ResolveMethodParams('    public static int argh(String str, int i) throws Exception1, Exception2 {')
  let s:appendPos = 1
  let s:indent = s:method_indent
  call s:AppendStr(s:method_returnValue)
  call s:AppendStr(s:method_paramList)
  call s:AppendStr(s:method_throwsList)
  let l:param = s:GetNextParameterName()
  while l:param !=# ''
    call s:AppendStr(l:param)
    let l:param = s:GetNextParameterName()
  endwhile

  let l:exc = s:GetNextThrowName()
  while l:exc !=# ''
    call s:AppendStr(l:exc)
    let l:exc = s:GetNextThrowName()
  endwhile
endfunction

" ===================================================
" Functions to parse things
" ===================================================

function! s:ResolveMethodParams(methodHeader)
  let l:methodHeader = a:methodHeader
  let l:methodHeader = substitute(l:methodHeader, '^\(.\{-}\)\s*[{;].*', '\1', '')

  let s:appendPos = s:rangeStart - 1
  let s:method_indent = substitute(l:methodHeader, '^\(\s*\)\S.*', '\1', '')

  let l:preNameString = substitute(l:methodHeader, '^\(\(.*\)\s\)' . s:javaname . '\s*(.*', '\1', '')
  let s:method_returnValue = substitute(l:preNameString, '\(.*\s\|^\)\(' . s:javaname . '\(\s*\[\s*\]\)*\)\s*$', '\2', '')

  if s:method_returnValue ==# ''
    let s:debugstring .= 'isEmpty '
  endif

  if s:method_returnValue ==# 'void'
    let s:debugstring .= 'isVoid'
  endif

  if s:method_returnValue ==# 'void' || s:IsConstructor(l:methodHeader)
    let s:method_returnValue = ''
  endif

  let s:method_paramList = substitute(l:methodHeader, '.*(\(.*\)).*', '\1', '')
  let s:method_paramList = s:Trim(s:method_paramList)

  let s:method_throwsList = ''
  if l:methodHeader =~# ')\s*throws\s'
    let s:method_throwsList = substitute(l:methodHeader, '.*)\s*throws\s\+\(.\{-}\)\s*$', '\1', '')
  endif
endfunction

function! s:GetNextParameterName()
  let l:result = substitute(s:method_paramList, '.\{-}\s\+\(' . s:javaname . '\)\s*\(,.*\|$\)', '\1', '')
  if s:method_paramList !~# ','
    let s:method_paramList = ''
  else
    let l:endIndex = matchend(s:method_paramList, ',\s*')
    let s:method_paramList = strpart(s:method_paramList, l:endIndex)
  endif
  return l:result
endfunction

function! s:GetNextThrowName()
  let l:result = substitute(s:method_throwsList, '\s*\(' . s:javaname . '\)\s*\(,.*\|$\)', '\1', '')
  if match(s:method_throwsList, ',') == -1
    let s:method_throwsList = ''
  else
    let s:method_throwsList = substitute(s:method_throwsList, '.\{-},\s*\(.*\)', '\1', '')
  endif
  return l:result
endfunction

" ===================================================
" Functions to determine what is meant to be commented
" ===================================================

let s:empty_start = '\%(^\|\s\)'

let s:javaname = '[a-zA-Z_][a-zA-Z0-9_]*'

let s:brackets       = '\%(\s*\(\[\s*\]\)\=\s*\)'
let s:generic_angles = '\%(\%(\s*<\s*\%(?\|' . s:javaname . '\)\s*>\s*\)\|\s*\)'

let s:javaConstructorPattern = s:empty_start . '[A-Z][a-zA-Z0-9]*\s*('
let s:javaMethodPattern      = s:empty_start . s:javaname . '\s*(.*)\s*\%(throws\|{\|;\|$\)'
let s:javaMethodAntiPattern  = '='
let s:javaThrowPattern       = '\<throw\s*new\s*' . s:javaname
let s:javaClassPattern       = s:empty_start . '\%(class\|interface\)\s\+' . s:javaname
let s:javaVariablePattern    = s:empty_start . s:javaname . s:generic_angles
                           \ . s:brackets . s:javaname . s:brackets . '\%(;\|=.*;\)'

let s:singleLineCommentPattern = '^\s*/\*\*.*\*/\s*$'
let s:commentTagPattern        = '^\s*\*\=\s*@[a-zA-Z]\+\%(\s\|$\)'

function! s:IsExceptionDeclaration()
  return s:combinedString =~# s:javaThrowPattern
endfunction

function! s:IsFileComments()
  return s:rangeStart <= 1 && s:rangeStart == s:rangeEnd
endfunction

function! s:IsModeLine()
  return s:rangeStart == line('$') && s:combinedString =~# '^\s*$'
endfunction

function! s:IsSinglelineComment()
  return s:combinedString =~# s:singleLineCommentPattern
endfunction

function! s:IsCommentTag()
  return s:combinedString =~# s:commentTagPattern
endfunction

function! s:IsFunctionEnd()
  return s:combinedString =~# '^\s*}\s*$'
endfunction

function! s:IsConstructor(methodHeader)
  if a:methodHeader =~# s:javaConstructorPattern
    let s:debugstring .= 'IsConstructor'
  endif
  return a:methodHeader =~# s:javaConstructorPattern
endfunction

function! s:IsMethod()
  let l:str = s:combinedString
  return l:str =~# s:javaMethodPattern && l:str !~# s:javaMethodAntiPattern
endfunction

function! s:IsClass()
  return s:combinedString =~# s:javaClassPattern
endfunction

function! s:IsVariable()
  return s:combinedString =~# s:javaVariablePattern
endfunction

" Does the declaration already have comments?
function! s:HasMultilineDocComments()
  let l:linenum = s:rangeStart - 1
  let l:str = getline(l:linenum)
  while l:str =~# '^\s*$' && l:linenum > 1
    let l:linenum -= 1
    let l:str = getline(l:linenum)
  endwhile
  if l:str !~# '\*/\s*$' || l:str =~# '/\*\*.*\*/'
    return 0
  endif
  let s:docCommentEnd = l:linenum
  let l:linenum -= 1
  let l:str = getline(l:linenum)
  while l:str !~# '\%(/\*\|\*/\)' && l:linenum >= 1
    let l:linenum -= 1
    let l:str = getline(l:linenum)
  endwhile
  if l:str =~# '^\s*/\*\*'
    let s:docCommentStart = l:linenum
    return 1
  else
    let s:docCommentStart = -1
    let s:docCommentEnd   = -1
    return 0
  endif
endfunction

function! s:SearchPrevDocComments()
  let l:linenum = s:rangeStart - 1
  while 1
    let l:str = getline(l:linenum)
    while l:str !~# '\*/' && l:linenum > 1
      let l:linenum -= 1
      let l:str = getline(l:linenum)
    endwhile
    if l:linenum <= 1
      return 0
    endif
    let s:docCommentEnd = l:linenum
    let l:linenum -= 1
    let l:str = getline(l:linenum)
    while l:str !~# '\(/\*\|\*/\)' && l:linenum >= 1
      let l:linenum -= 1
      let l:str = getline(l:linenum)
    endwhile
    if l:str =~# '^\s*/\*\*'
      let s:docCommentStart = l:linenum
      return 1
    else
      if l:linenum == 1
        let s:docCommentStart = -1
        let s:docCommentEnd   = -1
        return 0
      endif
    endif
  endwhile
endfunction

function! s:HasSingleLineDocComments()
  let l:linenum = s:rangeStart - 1
  let l:str = getline(l:linenum)
  while l:str =~# '^\s*$' && l:linenum > 1
    let l:linenum -= 1
    let l:str = getline(l:linenum)
  endwhile
  if l:str =~# s:singleLineCommentPattern
    let s:singleLineCommentPos = l:linenum
    let s:docCommentStart = l:linenum
    let s:docCommentEnd   = l:linenum
    return v:true
  endif
  return v:false
endfunction

function! s:HasDocComments()
  if s:HasSingleLineDocComments()
    return 1
  elseif s:HasMultilineDocComments()
    return 2
  endif
endfunction

" ===================================================
" Utility functions
" ===================================================

function! s:GetIndentation(string)
  return substitute(a:string, '^\(\s*\).*', '\1', '')
endfunction

" returns one string combined from the strings on the given range.
function! s:GetCombinedString(rangeStart, rangeEnd)
  let l:line           = a:rangeStart
  let l:combinedString = getline(l:line)

  while l:line < a:rangeEnd
    let l:line += 1
    let l:combinedString .= ' ' . getline(l:line)
  endwhile

  return substitute(l:combinedString, '^\([^;{]*[;{]\=\).*', '\1', '')
endfunction

function! s:AppendStars(amount)
  let l:i = a:amount
  while l:i > 0
    call s:AppendStr(' * ')
    let l:i -= 1
  endwhile
endfunction

function! s:MoveCursor()
  if !g:jcommenter_move_cursor
    return
  endif
  let l:startInsert = g:jcommenter_autostart_insert_mode
  if g:jcommenter_description_starts_from_first_line
    call cursor(s:rangeStart, 99999)     " Arbitrary big number
  else
    call cursor(s:rangeStart + 1, 99999)
  endif
  if l:startInsert
    startinsert!
  endif
endfunction

let s:appendPos = 1

" A function for appending strings to the buffer.
" First set the 's:appendPos', then call this function repeatedly to append
" strings after that position.
function! s:AppendStr(string)
  call append(s:appendPos, s:indent . a:string)
  let s:appendPos += 1
endfunction

function! s:AddEmpty()
  if g:jcommenter_add_empty_line
    if getline(s:rangeStart - 1) !~# '^\s*$'
      call append(s:rangeStart - 1, '') " No need to add indent in empty line
                                        " so not using AppendStr
    endif
  endif
endfunction

function! s:Trim(string)
  return substitute(a:string, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

function! s:Message(string)
  echo '[JCommenter] ' . a:string
endfunction

"===============================================
let s:noCommentTrunk    = '^\s*\/\*\*\s*\n\%(\s*\*\s*\n\)*\%(\s*\*\s*@\|\s*\*\/\)'
let s:noParamTagComment = '^\s*\*\s*@\%(param\|throws\|exception\)\%(\s\+\h\w*\)\=\s*$'
let s:noTagComment      = '^\s*\*\s*@\%(return\|see\|version\|since\)\s*$'
let s:invalComments     = '\%(' . s:noCommentTrunk . '\)\|\%(' . s:noParamTagComment
                      \ . '\)\|\%(' . s:noTagComment . '\)'

function! SearchInvalidComment(backwards)
  let l:param = a:backwards ? 'wb' : 'w'
  if a:backwards
    if !g:jcommenter_description_starts_from_first_line && getline('.') =~# '^\s*\*\s*$'
      normal! k
    endif
    normal! k$
  endif
  let l:result = search(s:invalComments, l:param)
  if l:result > 0
    if !g:jcommenter_description_starts_from_first_line
      let l:isTrunk = (getline('.') =~# '^\s*\/\*\*')
      if l:isTrunk
        normal! j
      endif
    endif
    normal! $zz
  else
    call s:Message('No invalid comments found')
  endif
endfunction

function! ConditionalWriter()
  let l:line = getline('.')
  let l:doDoc = (l:line =~# s:javaMethodPattern)
  let l:doDoc2 = (l:line =~# s:javaConstructorPattern)
  let l:doDoc3 = (l:line =~# s:javaClassPattern)
  if l:doDoc || l:doDoc2 || l:doDoc3
    let l:oldmove = g:jcommenter_move_cursor
    let g:jcommenter_move_cursor = 0
    call JCommentWriter()
    let g:jcommenter_move_cursor = l:oldmove
  endif
endfunction

" vim:et sw=2 ts=2 tw=100
