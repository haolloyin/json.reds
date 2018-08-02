Red/System []

#enum json-type! [
    JSON_NULL: 1
    JSON_FALSE: 2
    JSON_TRUE: 3
    JSON_NUMBER: 4
    JSON_STRING: 5
    JSON_ARRAY: 6
    JSON_OBJECT: 7
]

#enum json-parse-result! [
    PARSE_OK: 1
    PARSE_EXPECT_VALUE: 2
    PARSE_INVALID_VALUE: 3
    PARSE_ROOT_NOT_SINGULAR: 4
    PARSE_NUMBER_TOO_BIG: 5
    PARSE_MISS_QUOTATION_MARK: 6
    PARSE_INVALID_STRING_ESCAPE: 7
    PARSE_MISS_COMMA_OR_SQUARE_BRACKET: 8
    PARSE_MISS_KEY: 9
    PARSE_MISS_COLON: 10
    PARSE_MISS_COMMA_OR_CURLY_BRACKET: 11
]

;- Note: Red/System 不支持 union 联合体，
;-       所以只能在结果体里冗余 number/string/array 几种情况
json-value!: alias struct! [    ;- 用于承载解析后的结果
    type    [json-type!]        ;- 类型，见 json-type!
    num     [float!]            ;- 数值
    str     [c-string!]         ;- 字符串
    arr     [json-value!]       ;- 指向 json-value! 的数组，嵌套了自身类型的指针
    objptr  [int-ptr!]          ;- 指向 json-member! 即 JSON 对象的数组的地址
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

    expect: func [char [byte!]][
        assert _ctx/json/1 = char
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
        printf ["context-pop ret: %d^/" ret]
        ret
    ]

    ;------------- parsing functions ----------------
    make-string: func [
        bytes   [byte-ptr!]
        len     [integer!]
        return: [c-string!]
        /local  target end
    ][
        target: allocate len + 1
        copy-memory target bytes len
        end: target + len
        end/value: null-byte        ;- 补上终结符
        as-c-string target
    ]

    bytes-ptr!: alias struct! [
        bytes [byte-ptr!]
    ]

    parse-string-raw: func [
        "解析 JSON 字符串，把结果写入 bytes 指针和 len 指针"
        bytes-ptr   [bytes-ptr!]
        len-ptr     [int-ptr!]
        return:     [integer!]
        /local      head len p ch top ch-ptr ret end
    ][
        head: _ctx/top           ;- 记录字符串起始点，即开头的 "

        printf ["parse-string-raw json: %s^/" _ctx/json]
        printf ["parse-string-raw bytes-ptr: %d -> %d, bytes: %s^/" bytes-ptr bytes-ptr/bytes/value bytes-ptr/bytes]
        expect #"^""        ;- 字符串必定以双引号开头，跳到下一个字符

        p: _ctx/json
        forever [
            ch: p/1
            p: p + 1            ;- 先指向下一个字符
            ;printf ["parse-string-raw ch: %c^/" ch]
            switch ch [
                #"^"" [         ;- 字符串结束符
                    len: _ctx/top - head
                    printf ["parse-string-raw finish with len: %d^/" len]

                    ;- 取出栈中的字节流，空字符串可能会返回 0
                    bytes-ptr/bytes: context-pop len
                    len-ptr/value: len
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
            bytes-ptr   [bytes-ptr!]
            len-ptr     [int-ptr!]
            ret         [integer!]
    ][
        bytes-ptr: declare bytes-ptr!
        bytes-ptr/bytes: declare byte-ptr!
        len-ptr: declare int-ptr!

        ret: parse-string-raw bytes-ptr len-ptr
        if ret = PARSE_OK [
            set-string v bytes-ptr/bytes len-ptr/value
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
                    ret: PARSE_MISS_COMMA_OR_SQUARE_BRACKET
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

    parse-object: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local
            ret     [integer!]
            size    [integer!]
            key-ptr [bytes-ptr!]
            len-ptr [int-ptr!]
            target  [byte-ptr!]
            m       [json-member!]
            i       [integer!]
    ][
        expect #"{"
        parse-whitespace                            ;- 第一个元素前可能有空白符
        if _ctx/json/1 = #"}" [
            _ctx/json: _ctx/json + 1
            v/type: JSON_OBJECT
            v/len: 0
            v/objptr: null                          ;- 空对象
            return PARSE_OK
        ]

        ret: 0
        size: 0
        m: declare json-member!
        m/val: declare json-value!
        key-ptr: declare bytes-ptr!
        key-ptr/bytes: declare byte-ptr!

        len-ptr: declare int-ptr!

        forever [
            if _ctx/json/1 <> #"^"" [               ;- 不是 " 开头说明 key 不合法
                ret: PARSE_MISS_KEY
                break
            ]
 
            ;- 解析 key
            ret: parse-string-raw key-ptr len-ptr
            if ret <> PARSE_OK [
                ret: PARSE_MISS_KEY
                break
            ]
            m/key: make-string key-ptr/bytes len-ptr/value
            m/klen: len-ptr/value

            parse-whitespace
            if _ctx/json/1 <> #":" [
                ret: PARSE_MISS_COLON
                break
            ]
            expect #":"
            parse-whitespace

            ;- 解析 value
            printf ["    m: %d, m/val: %d^/" m m/val]
            init-value m/val                        ;- 必须，否则在 free-value 时会被释放掉
            ;m/val: as json-value! allocate size? json-value!
            ret: parse-value m/val
            if ret <> PARSE_OK [break]

            ;- 构造一个 json-member!
            printf ["    m/key: %s -> %d^/" m/key m/key]
            printf ["    m: %d^/" m]
            printf ["    m/val: %d^/" m/val]
            printf ["    m/val/type: %d^/" m/val/type]
            printf ["    m/val/num: %.1g^/" m/val/num]
            ;printf ["    m/val/str: %s^/" m/val/str]
            ;printf ["    m/val/arr: %d^/" m/val/arr]

            ;- 把 json-member! 复制到栈中
            target: context-push size? json-member!
            copy-memory target (as byte-ptr! m) (size? json-member!)
            size: size + 1
            m/key: null                             ;- 避免重复释放

            parse-whitespace                        ;- 每个元素结束后可能有空白符
            switch _ctx/json/1 [
                #"," [
                    _ctx/json: _ctx/json + 1        ;- 跳过逗号
                    parse-whitespace
                ]
                #"}" [
                    _ctx/json: _ctx/json + 1        ;- 对象结束，从栈中复制到 json-value!
                    v/type: JSON_OBJECT
                    v/len: size
                    size: size * size? json-member! ;- 从栈中弹出
                    target: allocate size
                    copy-memory target (context-pop size) size

                    v/objptr: as int-ptr! target    ;- 这里其实是 json-member! 数组

                    return PARSE_OK
                ]
                default [
                    ret: PARSE_MISS_COMMA_OR_CURLY_BRACKET
                    break
                ]
            ]
        ]
        
        ;- 这里只有当解析失败时才需要释放由 malloc 分配在栈中的内存，
        ;- 因为解析成功时，分配的内存是用于存放解析得到的值，由调用者释放
        free as byte-ptr! m/key
        i: 0
        while [i < size] [
            m: as json-member! (context-pop size? json-member!)
            free-value m/val
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
            #"{"    [return parse-object v]
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
        printf ["^/--------- origin json: %s^/" json]
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

    ;------------ Accessing functions -------------

    init-value: func [v [json-value!]][
        assert v <> null
        v/type: JSON_NULL
    ]

    free-value: func [v [json-value!] /local i e m][
        assert v <> null
        printf ["free type: %d^/" v/type]
        switch v/type [
            JSON_STRING [
                printf ["free-STRING v: %d, v/str: %d^/" v v/str]
                free as byte-ptr! v/str
            ]
            JSON_ARRAY  [
                printf ["free-ARRAY v: %d, v/arr: %d^/" v v/arr]
                ;- 递归释放数组中每一个元素
                i: 0
                while [i < v/len][
                    e: v/arr + i
                    free-value e            ;- value! 可能有 str 类型的元素，让它递归
                    i: i + 1
                ]
                free as byte-ptr! v/arr     ;- arr 本身也是 malloc 得到的
            ]
            JSON_OBJECT [
                ;- 递归释放对象中每一个元素
                i: 0
                printf ["free-OBJECT v: %d, v/objptr: %d^/" v v/objptr]
                while [i < v/len][
                    m: as json-member! (v/objptr + i)
                    free as byte-ptr! m/key
                    free-value m/val        ;- value 一定不为空
                    i: i + 1
                ]
                free as byte-ptr! v/objptr
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
        bytes   [byte-ptr!]
        len     [integer!]
        /local  target p
    ][
        assert all [
            v <> null
            any [bytes <> null len = 0]]      ;- 非空指针，或空字符串

        ;- 确保传入的 json-value! 中原有的 str/arr 被释放掉
        free-value v

        v/str: make-string bytes len
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

        member: (as json-member! v/objptr) + index
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

        member: (as json-member! v/objptr) + index
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

        member: (as json-member! v/objptr) + index
        member/val
    ]
]

