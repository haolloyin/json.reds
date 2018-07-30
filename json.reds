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
    PARSE_MISSING_COMMA_OR_SQUARE_BRACKET
]

;- Note: Red/System 不支持 union 联合体，
;-       所以只能在结果体里冗余 number/string/array 几种情况
json-value!: alias struct! [    ;- 用于承载解析后的结果
    type    [json-type!]        ;- 类型，见 json-type!
    num     [float!]            ;- 数值
    str     [c-string!]         ;- 字符串
    arr     [json-value!]       ;- 指向 json-value! 的数组，嵌套了自身类型的指针
    obj     [byte-ptr!]         ;- 指向 json-member! 即 JSON 对象的数组
    len     [integer!]          ;- 字符串长度 or 数组元素个数
]

json-member!: alias struct! [
    key     [c-string!]         ;- key
    klen    [integer!]          ;- key 的字符个数
    val     [json-value!]       ;- 值
]


json: context [
    _ctx: declare struct! [         ;- 用于承载解析过程的中间数据
        json    [c-string!]         ;- JSON 字符串
        stack   [byte-ptr!]         ;- 动态数组，按字节存储
        size    [integer!]          ;- 当前栈大小，按 byte 计
        top     [integer!]          ;- 可 push/pop 任意大小
    ]

    parse-whitespace: func [/local c][
        c: _ctx/json
        while [any [c/1 = space c/1 = tab c/1 = cr c/1 = lf]][
            c: c + 1
        ]
        _ctx/json: c
    ]

    expect: func [char [byte!] /local c][
        c: _ctx/json
        assert c/1 = char
        _ctx/json: _ctx/json + 1
    ]

    parse-null: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect #"n"

        str: _ctx/json
        if any [str/1 <> #"u" str/2 <> #"l" str/3 <> #"l" ][
            return PARSE_INVALID_VALUE
        ]

        _ctx/json: _ctx/json + 3
        v/type: JSON_NULL
        PARSE_OK
    ]

    parse-true: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect #"t"

        str: _ctx/json
        if any [str/1 <> #"r" str/2 <> #"u" str/3 <> #"e"][
            return PARSE_INVALID_VALUE
        ]

        _ctx/json: _ctx/json + 3
        v/type: JSON_TRUE
        PARSE_OK
    ]

    parse-false: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str
    ][
        expect #"f"

        str: _ctx/json
        if any [str/1 <> #"a" str/2 <> #"l" str/3 <> #"s" str/4 <> #"e" ][
            return PARSE_INVALID_VALUE
        ]

        _ctx/json: _ctx/json + 4
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
        v       [json-value!]
        return: [json-parse-result!]
        /local  c str end
    ][
        c: _ctx/json

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
        v/num: strtod as byte-ptr! _ctx/json null
        if null? c [return PARSE_INVALID_VALUE]

        _ctx/json: c    ;- 跳到成功转型后的下一个字节
        v/type: JSON_NUMBER
        PARSE_OK
    ]

    #define PUTC(ch) [
        top: context-push 1
        top/value: ch
    ]

    parse-string-raw: func [
        "解析 JSON 字符串，把结果写入 str 和 len"
        strarr  [str-array!]
        len-ptr [int-ptr!]
        return: [integer!]
        /local  head len p ch top ch-ptr ret
    ][
        head: _ctx/top           ;- 记录字符串起始点，即开头的 "

        ;printf ["begin parse-string: %s^/" _ctx/json]
        expect #"^""        ;- 字符串必定以双引号开头，跳到下一个字符

        p: _ctx/json
        forever [
            ch: p/1
            p: p + 1            ;- 先指向下一个字符
            ;printf ["parse-string ch: %c^/" ch]
            switch ch [
                #"^"" [         ;- 字符串结束符
                    len: _ctx/top - head
                    ;printf ["parse-string finish with len: %d^/" len]
                    ;- 从栈中取出所有字符来构造成 c-string!
                    strarr/item: as-c-string context-pop len
                    len-ptr/value: len

                    ;printf ["parse-string-raw str:%s^/" strarr/item]

                    _ctx/json: p

                    return PARSE_OK
                ]
                #"\" [
                    ch: p/1
                    p: p + 1
                    switch ch [
                        #"^""   [PUTC(#"^"")]
                        #"\"    [PUTC(#"\")]
                        #"/"    [PUTC(#"/")]
                        #"n"    [PUTC(#"^M")]
                        #"r"    [PUTC(#"^/")]
                        #"t"    [PUTC(#"^-")]
                        ;- TODO 这几个转义符不知道在 R/S 里怎么对应
                        ;#"b"    [PUTC(#"\b")]
                        ;#"f"    [PUTC(#"\f")]
                        default [
                            _ctx/top: head
                            return PARSE_INVALID_STRING_ESCAPE
                        ]
                    ]
                ]
                null-byte [
                    _ctx/top: head
                    return PARSE_MISS_QUOTATION_MARK    ;- 没有用 " 结尾
                ]
                default [
                    ;- TODO 非法字符
                    PUTC(ch)
                ]
            ]
        ]
        0
    ]

    parse-string: func [
        v       [json-value!]
        return: [integer!]
        /local
            strarr  [str-array!]
            len     [int-ptr!]
            ret     [integer!]
    ][
        strarr: declare str-array!
        len: declare int-ptr! 0

        ret: parse-string-raw strarr len
        if ret = PARSE_OK [
            set-string v (as byte-ptr! strarr/item) len/value
        ]

        ret
    ]

    parse-array: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  p ch e ret size target i
    ][
        size: 0
        expect #"["
        parse-whitespace                            ;- 第一个元素前可能有空白符

        if _ctx/json/1 = #"]" [
            _ctx/json: _ctx/json + 1
            v/type: JSON_ARRAY
            v/len: 0
            v/arr: null                             ;- 空数组
            return PARSE_OK
        ]

        forever [
            e: declare json-value!                  ;- 承载数组的元素
            init-value e
            parse-whitespace                        ;- 每个元素前可能有空白符

            ret: parse-value e                      ;- 解析元素，并用新的 json-value! 来承载
            if ret <> PARSE_OK [break]              ;- 解析元素失败，跳出 while 释放内存

            ;- 解析元素成功
            ;- 把 json-value! 结构入栈（其实是申请空间，返回可用的起始地址），
            ;- 用解析得到的元素来填充栈空间，释放掉这个临时 json-value! 结构
            target: context-push size? json-value!
            copy-memory target (as byte-ptr! e) (size? json-value!)

            size: size + 1

            parse-whitespace                        ;- 每个元素结束后可能有空白符

            ;printf ["array next char: %c^/" _ctx/json/1]
            switch _ctx/json/1 [
                #"," [
                    _ctx/json: _ctx/json + 1      ;- 跳过数组内的逗号
                ]
                #"]" [
                    _ctx/json: _ctx/json + 1      ;- 数组结束，从栈中复制到 json-value!
                    v/type: JSON_ARRAY
                    v/len: size

                    size: size * size? json-value!
                    target: allocate size       ;- 注意，这里用 malloc 分配内存
                    copy-memory target (context-pop size) size

                    v/arr: as json-value! target;- 这里其实是 json-value! 数组

                    return PARSE_OK
                ]
                default [
                    ;- 异常，元素后面既不是逗号，也不是方括号来结束
                    ;- 先保存解析结果，跳出 while 之后清理栈中已分配的内存
                    ret: PARSE_MISSING_COMMA_OR_SQUARE_BRACKET
                    break
                ]
            ]
        ]
        
        ;- 这里只有当解析失败时才需要释放由 malloc 分配在栈中的内存，
        ;- 因为解析成功时，分配的内存是用于存放解析得到的值，由调用者释放
        i: 0
        while [i < size] [
            free-value as json-value! (context-pop size? json-value!)
            i: i + 1
        ]

        ret
    ]

    parse-value: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  c
    ][
        c: _ctx/json

        switch c/1 [
            #"n"    [return parse-null v]
            #"t"    [return parse-true v]
            #"f"    [return parse-false v]
            #"^""   [return parse-string v]
            #"["    [return parse-array v]
            null-byte [
                ;print-line "    null-byte"
                return PARSE_EXPECT_VALUE
            ]
            default [
                ;print-line "    default: parse-number"
                return parse-number v
            ]
        ]
    ]

    parse: func [
        v       [json-value!]
        json    [c-string!]
        return: [json-parse-result!]
        /local  ret byte
    ][
        assert _ctx <> null

        _ctx/json:   json
        _ctx/stack:  null
        _ctx/size:   0
        _ctx/top:    0
        v/type:     JSON_NULL

        ;- 开始解析
        parse-whitespace                ;- 先清掉前置的空白
        ret: parse-value v

        if ret = PARSE_OK [
            parse-whitespace            ;- 再清理后续的空白
            byte: _ctx/json

            if byte/1 <> null-byte [
                print-line ["    terminated by not null-byte: " byte/1]
                v/type: JSON_NULL
                ret: PARSE_ROOT_NOT_SINGULAR
            ]
        ]

        ;- 清理空间
        assert _ctx/top = 0
        free _ctx/stack

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

    ;- 解析过程中入栈，其实是在栈中申请指定的 size 个 byte!，
    ;- 然后调用方把值写入这个申请到的空间，例如：
    ;-      1. string 的每一个字符
    ;-      2. 数组或对象的每一个元素（json-value! 结构）
    context-push: func [
        size    [integer!]
        return: [byte-ptr!]             ;- 返回可用的起始地址
        /local  ret
    ][
        assert size > 0

        ;- 栈空间不足
        if _ctx/top + size >= _ctx/size [
            ;- 首次初始化
            if _ctx/size = 0 [_ctx/size: PARSE_STACK_INIT_SIZE]

            while [_ctx/top + size >= _ctx/size][
                _ctx/size: _ctx/size + (_ctx/size >> 1)    ;- 每次加 2倍
            ]
            _ctx/stack: realloc _ctx/stack _ctx/size       ;- 重新分配内存
        ]

        ret: _ctx/stack + _ctx/top        ;- 返回数据起始的指针
        _ctx/top: _ctx/top + size         ;- 指向新的栈顶
        ret
    ]

    
    ;- pop 返回 byte-ptr!，由调用者根据情况补上末尾的 null 来形成 c-string!，
    ;- 因为栈不是只给 string 使用的，数组、对象都要用到
    context-pop: func [
        size    [integer!]
        return: [byte-ptr!]
        /local  ret
    ][
        assert _ctx/top >= size
        _ctx/top: _ctx/top - size         ;- 更新栈顶指针
        ret: _ctx/stack + _ctx/top        ;- 返回缩减后的栈顶指针：栈基地址 + 偏移

        ;- Note: 如果 json 是空字符串，这里返回的是地址 0，小心
        ;print-line ["context-pop ret: " ret "."]
        ret
    ]

    ;------------ Accessing functions -------------

    init-value: func [v [json-value!]][
        assert v <> null
        v/type: JSON_NULL
    ]

    free-value: func [v [json-value!] /local i e][
        assert v <> null
        switch v/type [
            JSON_STRING [free as byte-ptr! v/str]
            JSON_ARRAY  [
                ;- 递归释放数组中每一个元素
                i: 1
                while [i < v/len][
                    e: v/arr + i
                    free-value e
                    i: i + 1
                ]
                free as byte-ptr! v/arr
            ]
            default     []
        ]
        v/type: JSON_NULL 
    ]

    get-type: func [v [json-value!] return: [json-type!]][
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
            any [str <> null len = 0]]      ;- 非空指针，或空字符串

        ;- 确保传入的 json-value! 中的 str/arr 被释放掉
        free-value v

        target: allocate len + 1            ;- 包含字符串终结符

        ;- Note: pop 返回 byte-ptr! 是因为在这里补上末尾的 null 形成 c-string!
        ;- 如果 pop 返回 c-string! 好像挺难搞，会遇到偶数字节时末尾有异常字符
        copy-memory target str len

        p: target + len
        p/value: null-byte                  ;- 补上字符串终结符才能转成 c-string!
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

    get-array-size: func [v [json-value!] return: [integer!]][
        assert all [
            v <> null
            v/type = JSON_ARRAY]
        v/len
    ]

    get-array-element: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [json-value!]
    ][
        assert all [
            v <> null
            v/type = JSON_ARRAY]
        assert index < v/len

        v/arr + index           ;- 下标基于 0
    ]

    get-object-size: func [v [json-value!] return: [integer!]][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        v/len
    ]

    get-object-key: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [c-string!]
        /local  member
    ][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        assert index < v/len

        member: (as json-member! v/obj) + index
        member/key
    ]

    get-object-key-length: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [integer!]
        /local  member
    ][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        assert index < v/len

        member: (as json-member! v/obj) + index
        member/klen
    ]

    get-object-value: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [json-value!]
        /local  member
    ][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        assert index < v/len

        member: (as json-member! v/obj) + index
        member/val
    ]
]
