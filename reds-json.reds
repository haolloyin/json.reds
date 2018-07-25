Red/System []

#enum json-type! [
    JSON_NULL: 1
    JSON_FALSE
    JSON_TRUE
    JSON_NUMBER
    JSON_STRING
    JSON_ARRAY
    JSON_OBJECT
]

#enum json-parse-result! [
    PARSE_OK: 1
    PARSE_EXPECT_VALUE
    PARSE_INVALID_VALUE
    PARSE_ROOT_NOT_SINGULAR
    PARSE_NUMBER_TOO_BIG
    PARSE_MISS_QUOTATION_MARK
    PARSE_INVALID_STRING_ESCAPE
]

json-value!: alias struct! [
    type    [json-type!]    ;- 类型
    ;- Note: Red/System 不支持 union，所以只能冗余 num 和 str 两种情况
    num     [float!]        ;- 数值
    str     [c-string!]     ;- 字符串
    len     [integer!]      ;- 字符串长度
]

json-conetxt!: alias struct! [
    json    [c-string!]     ;- JSON 字符串
    stack   [byte-ptr!]     ;- 动态数组，按字节存储
    size    [integer!]      ;- 当前栈大小，按 byte 计
    top     [integer!]      ;- 可 push/pop 任意大小
]


json: context [
    parse-whitespace: func [
        ctx     [json-conetxt!]
        /local  c
    ][
        c: ctx/json
        while [any [c/1 = space c/1 = tab c/1 = cr c/1 = lf]][
            c: c + 1
        ]
        ctx/json: c
    ]

    expect: func [
        ctx     [json-conetxt!]
        char    [byte!]
        /local  c
    ][
        c: ctx/json
        assert c/1 = char
        ctx/json: ctx/json + 1
    ]

    parse-null: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect ctx #"n"

        str: ctx/json
        if any [str/1 <> #"u" str/2 <> #"l" str/3 <> #"l" ][
            return PARSE_INVALID_VALUE
        ]

        ctx/json: ctx/json + 3
        v/type: JSON_NULL
        PARSE_OK
    ]

    parse-true: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect ctx #"t"

        str: ctx/json
        if any [str/1 <> #"r" str/2 <> #"u" str/3 <> #"e"][
            return PARSE_INVALID_VALUE
        ]

        ctx/json: ctx/json + 3
        v/type: JSON_TRUE
        PARSE_OK
    ]

    parse-false: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect ctx #"f"

        str: ctx/json
        if any [str/1 <> #"a" str/2 <> #"l" str/3 <> #"s" str/4 <> #"e" ][
            return PARSE_INVALID_VALUE
        ]

        ctx/json: ctx/json + 4
        v/type: JSON_FALSE
        PARSE_OK
    ]

    #define ISDIGIT(v)      [all [v >= #"0" v <= #"9"]]
    #define ISDIGIT1TO9(v)  [all [v >= #"1" v <= #"9"]]
    #define JUMP_TO_NOT_DIGIT [
        until [
            c: c + 1
            not ISDIGIT(c/1)    ;- 不是数字则跳出
        ]
    ]

    parse-number: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str end
    ][
        c: ctx/json

        ;- 校验格式
        if c/1 = #"-" [c: c + 1]

        either c/1 = #"0" [c: c + 1][
            ;- 不是 0 开头，接下来必须是 1~9，否则报错
            if not ISDIGIT1TO9(c/1) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        if c/1 = #"." [
            c: c + 1
            if not ISDIGIT(c/1) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        if any [c/1 = #"e" c/1 = #"E"][
            c: c + 1
            if any [c/1 = #"+" c/1 = #"-"][c: c + 1]
            if not ISDIGIT(c/1) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        ;- TODO: 不知道怎么实现数字过大时要用 errno 判断 ERANGE、HUGE_VAL 几个宏的问题
        ;- SEE https://zh.cppreference.com/w/c/string/byte/strtof
        v/num: strtod as byte-ptr! ctx/json null
        if null? c [return PARSE_INVALID_VALUE]

        ctx/json: c    ;- 跳到成功转型后的下一个字节
        v/type: JSON_NUMBER
        PARSE_OK
    ]

    #define PUTC(ctx ch) [
        top: context-push ctx 1
        top/value: ch
    ]

    parse-string: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [integer!]
        /local  head len p ch top
    ][
        head: ctx/top       ;- 记录字符串起始点，即开头的 "

        ;print-line ["begin parse-string: " ctx/json]
        expect ctx #"^""    ;- 字符串必定以双引号开头，跳到下一个字符

        p: ctx/json
        forever [
            ch: p/1
            p: p + 1        ;- 先指向下一个字符
            ;print-line ["parse-string ch: " ch]
            switch ch [
                #"^"" [     ;- 字符串结束符
                    len: ctx/top - head
                    ;print-line ["parse-string finish with len: " len]
                    set-string v (context-pop ctx len) len
                    ctx/json: p
                    return PARSE_OK
                ]
                #"\" [
                    ch: p/1
                    p: p + 1
                    switch ch [
                        #"^""   [PUTC(ctx #"^"")]
                        #"\"    [PUTC(ctx #"\")]
                        #"/"    [PUTC(ctx #"/")]
                        #"n"    [PUTC(ctx #"^M")]
                        #"r"    [PUTC(ctx #"^/")]
                        #"t"    [PUTC(ctx #"^-")]
                        ;- TODO 这几个转义符不知道在 R/S 里怎么对应
                        ;#"b"    [PUTC(ctx #"\b")]
                        ;#"f"    [PUTC(ctx #"\f")]
                        default [
                            ctx/top: head
                            return PARSE_INVALID_STRING_ESCAPE
                        ]
                    ]
                ]
                null-byte [
                    ctx/top: head
                    return PARSE_MISS_QUOTATION_MARK    ;- 没有用 " 结尾
                ]
                default [
                    ;- TODO 非法字符
                    PUTC(ctx ch)
                ]
            ]
        ]
        0
    ]

    parse-value: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c
    ][
        c: ctx/json

        switch c/1 [
            #"n"    [return parse-null ctx v]
            #"t"    [return parse-true ctx v]
            #"f"    [return parse-false ctx v]
            #"^""   [return parse-string ctx v]
            null-byte [
                ;print-line "    null-byte"
                return PARSE_EXPECT_VALUE
            ]
            default [
                ;print-line "    default: parse-number"
                return parse-number ctx v
            ]
        ]
    ]

    parse: func [
        v       [json-value!]
        json    [c-string!]
        return: [json-parse-result!]
        /local  ctx ret byte
    ][
        ctx: declare json-conetxt!  ;- 用于装载解析过程中的内容
        assert ctx <> null

        ctx/json:   json
        ctx/stack:  null
        ctx/size:   0
        ctx/top:    0
        v/type:     JSON_NULL

        ;- 开始解析
        parse-whitespace ctx        ;- 先清掉前置的空白
        ret: parse-value ctx v

        if ret = PARSE_OK [
            parse-whitespace ctx    ;- 再清理后续的空白
            byte: ctx/json

            if byte/1 <> null-byte [
                print-line ["    terminated by not null-byte: " byte/1]
                v/type: JSON_NULL
                ret: PARSE_ROOT_NOT_SINGULAR
            ]
        ]

        ;- 清理空间
        assert ctx/top = 0
        free ctx/stack

        ret
    ]

    ;------------- stack functions ----------------
    #define PARSE_STACK_INIT_SIZE 256   ;- 初始的栈大小
    #import [
        LIBC-file cdecl [
            realloc:    "realloc" [
                ptr     [byte-ptr!]
                size    [integer!]
                return: [byte-ptr!]
            ]
        ]
    ]

    context-push: func [
        ctx     [json-conetxt!]
        size    [integer!]
        return: [byte-ptr!]
        /local  ret
    ][
        assert size > 0

        ;- 栈空间不足
        if ctx/top + size >= ctx/size [
            ;- 首次初始化
            if ctx/size = 0 [
                ctx/size: PARSE_STACK_INIT_SIZE
            ]

            while [ctx/top + size >= ctx/size][
                ctx/size: ctx/size + (ctx/size >> 1)    ;- 每次加 2倍
            ]
            ctx/stack: realloc ctx/stack ctx/size       ;- 重新分配内存
        ]

        ret: ctx/stack + ctx/top    ;- 返回数据起始的指针
        ctx/top: ctx/top + size     ;- 指向新的栈顶
        ret
    ]

    context-pop: func [
        ctx     [json-conetxt!]
        size    [integer!]
        return: [byte-ptr!]
        /local  ret
    ][
        assert ctx/top >= size
        ctx/top: ctx/top - size
        ret: ctx/stack + ctx/top         ;- 返回缩减后的栈顶指针
        ;- Note: 如果是空字符串，这里返回的是地址 0，小心
        ;print-line ["context-pop ret: " ret "."]
        ret
    ]

    ;------------ Accessing functions -------------

    init-value: func [v [json-value!]][
        assert v <> null
        v/type: JSON_NULL
    ]

    free-value: func [v [json-value!]][
        assert v <> null
        if v/type = JSON_STRING [free as byte-ptr! v/str]
        v/type: JSON_NULL 
    ]

    get-type: func [
        v       [json-value!]
        return: [json-type!]
    ][
        assert v <> null
        v/type
    ]

    set-number: func [v [json-value!] num [float!]][
        free-value v
        v/num: num
        v/type: JSON_NUMBER
    ]

    get-number: func [v [json-value!] return: [float!]][
        assert all [
            v <> null
            v/type = JSON_NUMBER]

        v/num
    ]

    set-boolean: func [v [json-value!] b [logic!]][
        free-value v
        v/type: either b [JSON_TRUE][JSON_FALSE]
    ]

    get-boolean: func [v [json-value!] return: [logic!]][
        assert all [
            v <> null
            any [v/type = JSON_FALSE v/type = JSON_TRUE]]

        v/type = JSON_TRUE
    ]

    set-string: func [
        v       [json-value!]
        str     [byte-ptr!]
        len     [integer!]
        /local  target p
    ][
        assert all [
            v <> null
            any [str <> null len = 0]]          ;- 非空指针，或空字符串

        free-value v    ;- 确保原本的 v 可能是已经分配过的 string 被释放掉

        target: allocate len + 1  ;- 包含字符串终结符

        ;- Note: pop 返回 byte-ptr! 是因为由用户手工补上末尾的 null 更好
        copy-memory target str len

        p: target + len
        p/value: null-byte  ;- 补上字符串终结符才能转成 c-string!
        v/str: as-c-string target
        v/len: len
        v/type: JSON_STRING
    ]

    get-string: func [v [json-value!] return: [c-string!]][
        assert all [
            v <> null
            v/type = JSON_STRING
            v/str <> null]

        v/str
    ]

    get-string-length: func [v [json-value!] return: [integer!]][
        assert all [
            v <> null
            v/type = JSON_STRING
            v/str <> null]

        v/len
    ]
]

comment {
    JSON syntax ABNF:

    JSON-text = ws value ws
        ws = *(%x20 / %x09 / %x0A / %x0D)
        value = null / false / true 
        null  = "null"
        false = "false"
        true  = "true"

    number = [ "-" ] int [ frac ] [ exp ]
    int = "0" / digit1-9 *digit
    frac = "." 1*digit
    exp = ("e" / "E") ["-" / "+"] 1*digit
}

