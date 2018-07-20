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
]

json-value!: alias struct! [
    type    [json-type!]    ;- 类型
    num     [float!]        ;- 数值
]

json-conetxt!: alias struct! [
    json    [byte-ptr!]     ;- JSON 字符串
]


json: context [
    parse-whitespace: func [
        ctx     [json-conetxt!]
        /local  c s
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
        assert c/value = char
        ctx/json: ctx/json + 1
    ]

    parse-null: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect ctx #"n"

        str: as-c-string ctx/json
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

        str: as-c-string ctx/json   ;- 转成 c-string! 方便用 /i 下标语法
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

        str: as-c-string ctx/json
        if any [str/1 <> #"a" str/2 <> #"l" str/3 <> #"s" str/4 <> #"e" ][
            return PARSE_INVALID_VALUE
        ]

        ctx/json: ctx/json + 4
        v/type: JSON_FALSE
        PARSE_OK
    ]

    #define ISDIGIT(v) [all [#"0" <= v v <= #"9"]]
    #define ISDIGIT1TO9(v) [all [#"1" <= v v <= #"9"]]
    #define JUMP_TO_NOT_DIGIT [
        until [
            c: c + 1
            ISDIGIT(c/value)    ;- 跳到下一个非数字的位置
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
        if c/value = #"-" [c: c + 1]

        either c/value = #"0" [c: c + 1][
            ;- 不是 0 开头，接下来必须是 1~9，否则报错
            if not ISDIGIT1TO9(c/value) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        if c/value = #"." [
            c: c + 1
            if not ISDIGIT(c/value) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        if any [c/value = #"e" c/value = #"E"][
            c: c + 1
            if any [c/value = #"+" c/value = #"-"][c: c + 1]
            if not ISDIGIT(c/value) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        ;- TODO: 不知道怎么实现数字过大时要用 errno 判断 ERANGE、HUGE_VAL 几个宏的问题
        ;- SEE https://zh.cppreference.com/w/c/string/byte/strtof
        v/num: strtod ctx/json null
        ;if null? c [return PARSE_INVALID_VALUE]

        ctx/json: c     ;- 跳到成功转型后的下一个字节
        v/type: JSON_NUMBER
        PARSE_OK
    ]

    parse-value: func [
        ctx     [json-conetxt!]
        v       [json-value!]
        return: [json-parse-result!]
        /local  c
    ][
        c: ctx/json
        ;print-line ["char: " c/value]

        switch c/value [
            #"n"    [return parse-null ctx v]
            #"t"    [return parse-true ctx v]
            #"f"    [return parse-false ctx v]
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
        ctx: declare json-conetxt!
        assert ctx <> null

        ctx/json: as byte-ptr! json
        v/type: JSON_NULL

        parse-whitespace ctx        ;- 先清掉前置的空白

        ret: parse-value ctx v
        if ret = PARSE_OK [
            parse-whitespace ctx    ;- 再清理后续的空白
            byte: ctx/json
            if byte/value <> null-byte [
                ;print-line "    terminated not by null-byte"
                ret: PARSE_ROOT_NOT_SINGULAR
            ]
        ]
        ret
    ]

    get-type: func [
        v       [json-value!]
        return: [json-type!]
    ][
        assert v <> null
        v/type
    ]

    get-number: func [
        v       [json-value!]
        return: [float!]
    ][
        assert all [
            v <> null
            v/type = JSON_NUMBER
        ]
        v/num
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

