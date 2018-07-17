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
    PARSE_OK: 10
    PARSE_EXPECT_VALUE
    PARSE_INVALID_VALUE
    PARSE_ROOT_NOT_SINGULAR
]

json-value!: alias struct! [
    type [json-type!]
]

json-conetxt!: alias struct! [
    json [byte-ptr!]
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
                print-line "    null-byte"
                return PARSE_EXPECT_VALUE
            ]
            default [
                print-line "    default"
                return PARSE_INVALID_VALUE
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
                print-line "    terminated not by null-byte"
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
]

comment {
    JSON syntax ABNF:

    JSON-text = ws value ws
        ws = *(%x20 / %x09 / %x0A / %x0D)
        value = null / false / true 
        null  = "null"
        false = "false"
        true  = "true"
}

