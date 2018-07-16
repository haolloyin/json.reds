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
        /local  c str
    ][
        c: ctx/json
        while [any [
                c/value = space
                c/value = tab
                c/value = cr
                c/value = lf]][c: c + 1]
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
        if any [
            str/1 <> #"u"
            str/2 <> #"l"
            str/3 <> #"l"
        ][return PARSE_INVALID_VALUE]

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

        str: as-c-string ctx/json
        if any [
            str/1 <> #"r"
            str/2 <> #"u"
            str/3 <> #"e"
        ][return PARSE_INVALID_VALUE]

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
        if any [
            str/1 <> #"a"
            str/2 <> #"l"
            str/3 <> #"s"
            str/4 <> #"e"
        ][return PARSE_INVALID_VALUE]

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
        ;- switch 不能用 null，且 R/S 没有 '\0' 对应的值
        if null? c [return PARSE_EXPECT_VALUE]

        switch c/value [
            #"n"    [return parse-null ctx v]
            #"t"    [return parse-true ctx v]
            #"f"    [return parse-false ctx v]
            default [return PARSE_INVALID_VALUE]
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

        parse-whitespace ctx

        ret: parse-value ctx v
        if ret = PARSE_OK [
            parse-whitespace ctx
            byte: ctx/json
            if byte <> null [
                print-line "is not null"
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



