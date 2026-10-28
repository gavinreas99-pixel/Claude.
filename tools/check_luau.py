"""Lightweight Luau checker for this repo's scripts.

Catches the mistakes that usually break a Roblox script before you ever press
Play: syntax errors, misspelled locals/globals, and wrong Roblox names.

  python3 tools/check_luau.py src/BugCatcher [--api path/to/Full-API-Dump.json]

Checks:
  * full Lua 5.1 + Luau syntax used in this repo (continue, compound
    assignment, if-expressions, `::` casts are not supported on purpose)
  * reading or assigning an undefined variable (typos, missing `local`)
  * unused locals (warning)
  * with an API dump (Roblox-Client-Tracker "Full-API-Dump.json"):
      - Instance.new("Class") / game:GetService("Service") names exist
      - `x.Prop = value` where x came from Instance.new/GetService/create():
        the property exists and scripts may write it
      - `x:Method()` on those values: the method exists
      - create("Class", { Prop = ... }) property names
      - Enum.Type.Item names
  * members of built-in libraries (math., table., CFrame., Vector3. ...)
"""
import json
import re
import sys
from pathlib import Path

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

GLOBALS = {
    "game", "workspace", "script", "plugin", "shared", "_G", "Enum", "Instance", "require",
    "print", "warn", "error", "assert", "pcall", "xpcall", "type", "typeof", "tostring",
    "tonumber", "pairs", "ipairs", "next", "select", "unpack", "rawget", "rawset", "rawequal",
    "rawlen", "setmetatable", "getmetatable", "tick", "time", "elapsedTime", "wait", "delay",
    "spawn", "gcinfo", "newproxy",
    "math", "string", "table", "os", "task", "coroutine", "utf8", "bit32", "debug", "buffer",
    "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "BrickColor", "Ray", "Region3",
    "NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint",
    "NumberRange", "Rect", "TweenInfo", "PhysicalProperties", "RaycastParams",
    "OverlapParams", "Random", "DateTime", "Font", "Faces", "Axes", "PathWaypoint",
    "Vector3int16", "Vector2int16", "Region3int16", "SharedTable", "Content", "vector",
}

LIBS = {
    "math": "abs acos asin atan atan2 ceil clamp cos cosh deg exp floor fmod frexp huge ldexp "
            "log log10 max min modf noise pi pow rad random randomseed round sign sin sinh sqrt "
            "tan tanh lerp map isnan isinf isfinite",
    "string": "byte char find format gmatch gsub len lower match rep reverse split sub upper pack "
              "packsize unpack",
    "table": "clear clone concat create find freeze insert isfrozen maxn move pack remove sort unpack",
    "os": "clock date difftime time",
    "task": "spawn defer delay wait cancel synchronize desynchronize",
    "coroutine": "create isyieldable resume running status wrap yield close",
    "CFrame": "new Angles fromEulerAnglesXYZ fromEulerAnglesYXZ fromEulerAngles lookAt "
              "lookAlong fromAxisAngle fromMatrix fromOrientation identity",
    "Vector3": "new zero one xAxis yAxis zAxis FromNormalId FromAxis",
    "Vector2": "new zero one xAxis yAxis",
    "Color3": "new fromRGB fromHSV fromHex toHSV",
    "UDim": "new",
    "UDim2": "new fromScale fromOffset",
    "BrickColor": "new random Random White Black Red Blue Green Yellow Gray DarkGray palette",
    "NumberSequence": "new", "NumberSequenceKeypoint": "new", "ColorSequence": "new",
    "ColorSequenceKeypoint": "new", "NumberRange": "new", "TweenInfo": "new", "Random": "new",
    "RaycastParams": "new", "OverlapParams": "new", "Rect": "new", "Font": "new fromEnum fromName fromId",
    "Instance": "new fromExisting", "DateTime": "now fromUnixTimestamp fromUnixTimestampMillis",
    "PhysicalProperties": "new", "Ray": "new", "utf8": "char charpattern codes codepoint len offset",
}
LIBS = {k: set(v.split()) for k, v in LIBS.items()}

# Wrapper functions in this repo that set properties from a table:
# name -> (class: argument index or fixed class name, props: argument index)
#   create("ClassName", { Prop = value })
#   decor({ Prop = value })                       -> always a Part
#   findOrCreate(parent, "ClassName", { ... })
CREATE_FUNCS = {"create": (0, 1), "decor": ("Part", 0), "findOrCreate": (1, 2)}
# Helpers that return an instance of the class named by one of their arguments.
CLASS_FUNCS = {"waitForClass": 1}


class CheckError(Exception):
    pass


# --------------------------------------------------------------------------- lexer

TOKEN_RE = re.compile(
    r"""
    (?P<ws>[ \t\r]+)
  | (?P<nl>\n)
  | (?P<comment>--(?:\[(?P<ceq>=*)\[[\s\S]*?\](?P=ceq)\]|[^\n]*))
  | (?P<lstring>\[(?P<seq>=*)\[[\s\S]*?\](?P=seq)\])
  | (?P<string>"(?:\\[\s\S]|[^"\\\n])*"|'(?:\\[\s\S]|[^'\\\n])*')
  | (?P<interp>`(?:\\[\s\S]|[^`\\])*`)
  | (?P<number>0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.=|//=|\.\.|==|~=|<=|>=|\+=|-=|\*=|/=|%=|\^=|//|::|->|[-+*/%^\#<>=(){}\[\];:,.?|&])
    """,
    re.X,
)


def lex(src, path):
    tokens = []
    pos, line = 0, 1
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise CheckError(f"{path}:{line}: unexpected character {src[pos]!r}")
        kind = m.lastgroup
        text = m.group(0)
        if kind in ("comment", "lstring") or kind == "ceq" or kind == "seq":
            kind = "comment" if text.startswith("--") else "string"
        if kind == "name" and text in KEYWORDS:
            kind = text
        if kind == "op":
            kind = text
        if kind == "interp":
            tokens += lex_interpolation(text, path, line)
        elif kind not in ("ws", "nl", "comment"):
            value = text
            if kind == "string":
                value = decode_string(text)
            tokens.append((kind, value, line))
        line += text.count("\n")
        pos = m.end()
    tokens.append(("<eof>", "", line))
    return tokens


def lex_interpolation(text, path, line):
    # `a{b}c` is checked as ("a" .. tostring(b) .. "c").
    out = [("(", "(", line), ("string", "", line)]
    body, i = text[1:-1], 0
    literal = ""
    while i < len(body):
        ch = body[i]
        if ch == "\\":
            literal += body[i:i + 2]
            i += 2
        elif ch == "{":
            depth, j = 1, i + 1
            while j < len(body) and depth:
                depth += {"{": 1, "}": -1}.get(body[j], 0)
                j += 1
            if depth:
                raise CheckError(f"{path}:{line}: unclosed '{{' in interpolated string")
            out += [("..", "..", line), ("string", literal, line), ("..", "..", line),
                    ("name", "tostring", line), ("(", "(", line)]
            out += lex(body[i + 1:j - 1], path)[:-1]
            out.append((")", ")", line))
            literal = ""
            i = j
        else:
            literal += ch
            i += 1
    out += [("..", "..", line), ("string", literal, line), (")", ")", line)]
    return [(k, v, line) for k, v, _ in out]


def decode_string(text):
    if text.startswith("["):
        return re.sub(r"^\[=*\[\n?|\]=*\]$", "", text)
    return text[1:-1]


# --------------------------------------------------------------------------- API

class Api:
    def __init__(self, path):
        data = json.loads(Path(path).read_text())
        self.classes = {c["Name"]: c for c in data["Classes"]}
        self.enums = {e["Name"]: {i["Name"] for i in e["Items"]} for e in data["Enums"]}

    def chain(self, cls):
        while cls and cls in self.classes:
            yield self.classes[cls]
            cls = self.classes[cls].get("Superclass")

    def member(self, cls, name):
        for c in self.chain(cls):
            for m in c["Members"]:
                if m["Name"] == name:
                    return m
        return None

    def is_service(self, cls):
        c = self.classes.get(cls)
        return c is not None and "Service" in (c.get("Tags") or [])

    def creatable(self, cls):
        c = self.classes.get(cls)
        return c is not None and "NotCreatable" not in (c.get("Tags") or [])


# --------------------------------------------------------------------------- parser

class Var:
    __slots__ = ("name", "line", "used", "cls", "assigned")

    def __init__(self, name, line, cls=None):
        self.name, self.line, self.used, self.cls = name, line, False, cls
        self.assigned = cls is not None


class Val:
    """What the checker knows about an expression."""
    __slots__ = ("cls", "var", "lvalue", "call", "string", "index_of", "key", "table_keys", "global_lib")

    def __init__(self, **kw):
        for s in self.__slots__:
            setattr(self, s, kw.get(s))


BINARY_PRIORITY = {
    "or": (1, 1), "and": (2, 2),
    "<": (3, 3), ">": (3, 3), "<=": (3, 3), ">=": (3, 3), "~=": (3, 3), "==": (3, 3),
    "..": (5, 4),  # right associative
    "+": (6, 6), "-": (6, 6),
    "*": (7, 7), "/": (7, 7), "//": (7, 7), "%": (7, 7),
    "^": (10, 9),  # right associative
}
UNARY_PRIORITY = 8
COMPOUND = {"+=", "-=", "*=", "/=", "//=", "%=", "^=", "..="}


class Parser:
    def __init__(self, tokens, path, api, report):
        self.toks, self.i, self.path, self.api, self.report = tokens, 0, path, api, report
        self.scopes = []
        self.loop_depth = [0]

    # -- token helpers
    @property
    def tok(self):
        return self.toks[self.i]

    def peek(self, n=1):
        return self.toks[min(self.i + n, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def check(self, kind):
        return self.tok[0] == kind

    def accept(self, kind):
        if self.tok[0] == kind:
            return self.next()
        return None

    def expect(self, kind, what=None):
        if self.tok[0] != kind:
            raise CheckError(f"{self.path}:{self.tok[2]}: expected {what or repr(kind)} near {self.tok[1]!r}")
        return self.next()

    def error(self, line, msg):
        self.report("error", self.path, line, msg)

    def warn(self, line, msg):
        self.report("warning", self.path, line, msg)

    # -- scopes
    def open_scope(self):
        self.scopes.append({})

    def close_scope(self):
        for var in self.scopes.pop().values():
            if not var.used and not var.name.startswith("_") and var.name != "self":
                self.warn(var.line, f"unused local '{var.name}'")

    def declare(self, name, line, cls=None):
        var = Var(name, line, cls)
        self.scopes[-1][name] = var
        return var

    def resolve(self, name):
        for scope in reversed(self.scopes):
            if name in scope:
                return scope[name]
        return None

    # -- API checks
    def check_class(self, cls, line, service=False):
        if not self.api:
            return
        if service:
            if not self.api.is_service(cls):
                self.error(line, f"'{cls}' is not a Roblox service")
        elif cls not in self.api.classes:
            self.error(line, f"unknown class '{cls}'")
        elif not self.api.creatable(cls):
            self.error(line, f"class '{cls}' can't be created with Instance.new")

    def check_prop_write(self, cls, prop, line):
        if not self.api or cls not in self.api.classes:
            return
        m = self.api.member(cls, prop)
        if m is None:
            self.error(line, f"{cls} has no property '{prop}'")
            return
        if m["MemberType"] != "Property":
            self.error(line, f"{cls}.{prop} is a {m['MemberType']}, not a property")
            return
        tags = m.get("Tags") or []
        if "ReadOnly" in tags or "NotScriptable" in tags or m["Security"]["Write"] != "None":
            self.error(line, f"scripts can't set {cls}.{prop}")
        elif "Deprecated" in tags:
            self.warn(line, f"{cls}.{prop} is deprecated")

    def check_method(self, cls, name, line):
        if not self.api or cls not in self.api.classes:
            return
        m = self.api.member(cls, name)
        if m is None or m["MemberType"] != "Function":
            self.error(line, f"{cls} has no method '{name}'")
        elif m["Security"] != "None" if isinstance(m["Security"], str) else False:
            self.error(line, f"scripts can't call {cls}:{name}")

    def check_member_read(self, cls, name, line):
        # Reading x.Name where x is a known class: allowed if it's a member; children
        # can't be known statically, so only flag things that look like misspelled members.
        pass

    # -- grammar
    def chunk(self):
        self.open_scope()
        self.block()
        self.expect("<eof>", "end of file")
        self.close_scope()

    def block_follow(self):
        return self.tok[0] in ("else", "elseif", "end", "until", "<eof>")

    def block(self):
        while not self.block_follow():
            if self.check("return"):
                self.next()
                if not self.block_follow() and not self.check(";"):
                    self.explist()
                self.accept(";")
                if not self.block_follow():
                    raise CheckError(f"{self.path}:{self.tok[2]}: code after 'return'")
                return
            self.statement()
            self.accept(";")

    def scoped_block(self):
        self.open_scope()
        self.block()
        self.close_scope()

    def statement(self):
        kind, value, line = self.tok
        if kind == "if":
            self.next()
            self.expr()
            self.expect("then")
            self.scoped_block()
            while self.accept("elseif"):
                self.expr()
                self.expect("then")
                self.scoped_block()
            if self.accept("else"):
                self.scoped_block()
            self.expect("end", "'end' to close 'if' at line %d" % line)
        elif kind == "while":
            self.next()
            self.expr()
            self.expect("do")
            self.loop_body()
            self.expect("end", "'end' to close 'while' at line %d" % line)
        elif kind == "do":
            self.next()
            self.scoped_block()
            self.expect("end", "'end' to close 'do' at line %d" % line)
        elif kind == "for":
            self.next()
            first = self.expect("name", "loop variable")
            if self.accept("="):
                self.expr()
                self.expect(",")
                self.expr()
                if self.accept(","):
                    self.expr()
                names = [first]
            else:
                names = [first]
                while self.accept(","):
                    names.append(self.expect("name"))
                self.expect("in")
                self.explist()
            self.expect("do")
            self.open_scope()
            for n in names:
                self.declare(n[1], n[2])
            self.loop_body()
            self.close_scope()
            self.expect("end", "'end' to close 'for' at line %d" % line)
        elif kind == "repeat":
            self.next()
            self.open_scope()
            self.loop_depth[-1] += 1
            self.block()
            self.loop_depth[-1] -= 1
            self.expect("until")
            self.expr()
            self.close_scope()
        elif kind == "function":
            self.next()
            name = self.expect("name")
            target = self.name_ref(name, assign=True)
            is_method = False
            while self.check(".") or self.check(":"):
                is_method = self.next()[0] == ":"
                self.expect("name")
                if target:
                    target.used = True
                if is_method:
                    break
            self.funcbody(line, is_method)
        elif kind == "local":
            self.next()
            if self.accept("function"):
                name = self.expect("name")
                var = self.declare(name[1], name[2])
                var.used = var.used  # recursion allowed
                self.funcbody(line, False)
            else:
                names = [self.expect("name")]
                while self.accept(","):
                    names.append(self.expect("name"))
                vals = []
                if self.accept("="):
                    vals = self.explist()
                for idx, n in enumerate(names):
                    cls = vals[idx].cls if idx < len(vals) and vals[idx] else None
                    self.declare(n[1], n[2], cls)
        elif kind in ("break",):
            self.next()
            if self.loop_depth[-1] == 0:
                self.error(line, "'break' outside a loop")
        elif kind == "name" and value == "continue" and self.peek()[0] not in ("=", "(", ".", "[", ":", ",", '"', "{") and self.peek()[0] not in COMPOUND:
            self.next()
            if self.loop_depth[-1] == 0:
                self.error(line, "'continue' outside a loop")
        else:
            self.expr_statement()

    def loop_body(self):
        self.loop_depth[-1] += 1
        self.scoped_block()
        self.loop_depth[-1] -= 1

    def expr_statement(self):
        line = self.tok[2]
        target = self.suffixed_expr(lhs=True)
        if self.check("=") or self.check(","):
            targets = [target]
            while self.accept(","):
                targets.append(self.suffixed_expr(lhs=True))
            self.expect("=")
            vals = self.explist()
            for idx, t in enumerate(targets):
                self.assign(t, vals[idx] if idx < len(vals) else None, line)
        elif self.tok[0] in COMPOUND:
            self.next()
            self.expr()
            self.assign(target, None, line, compound=True)
        elif not target.call:
            raise CheckError(f"{self.path}:{line}: syntax error: expression is not a statement")

    def assign(self, target, val, line, compound=False):
        if target.lvalue is None:
            raise CheckError(f"{self.path}:{line}: can't assign to this expression")
        kind = target.lvalue
        if kind == "name":
            if target.var is None:
                self.error(line, f"assignment to undeclared global '{target.key}' (missing 'local'?)")
            else:
                if compound:
                    target.var.used = True
                var = target.var
                new_cls = val.cls if val is not None else None
                if not var.assigned:
                    var.cls, var.assigned = new_cls, True
                elif var.cls != new_cls:
                    var.cls = None  # holds different classes at different times: stop guessing
        elif kind == "field" and target.index_of is not None and target.index_of.cls:
            self.check_prop_write(target.index_of.cls, target.key, line)

    def name_ref(self, tok, assign=False):
        _, name, line = tok
        var = self.resolve(name)
        if var is None:
            if name not in GLOBALS:
                if assign:
                    self.error(line, f"assignment to undeclared global '{name}' (missing 'local'?)")
                else:
                    self.error(line, f"unknown variable '{name}'")
            return None
        if not assign:
            var.used = True
        return var

    def funcbody(self, line, is_method):
        self.expect("(")
        self.open_scope()
        self.loop_depth.append(0)
        if is_method:
            self.declare("self", line).used = True
        if not self.check(")"):
            while True:
                if self.accept("..."):
                    break
                p = self.expect("name", "parameter name")
                self.declare(p[1], p[2])
                if not self.accept(","):
                    break
        self.expect(")")
        self.block()
        self.loop_depth.pop()
        self.close_scope()
        self.expect("end", "'end' to close function at line %d" % line)

    def explist(self):
        vals = [self.expr()]
        while self.accept(","):
            vals.append(self.expr())
        return vals

    def primary_expr(self, lhs=False):
        kind, value, line = self.tok
        if kind == "name":
            self.next()
            var = self.resolve(value)
            if lhs and self.check_assign_ahead():
                # pure assignment target: don't mark as used
                if var is None and value not in GLOBALS:
                    pass
                return Val(lvalue="name", var=var, key=value, cls=var.cls if var else None)
            var = self.name_ref((kind, value, line))
            return Val(lvalue="name", var=var, key=value, cls=var.cls if var else None,
                       global_lib=value if var is None and value in GLOBALS else None)
        if kind == "(":
            self.next()
            v = self.expr()
            self.expect(")")
            return Val(cls=v.cls if v else None)
        raise CheckError(f"{self.path}:{line}: unexpected symbol near {value!r}")

    def check_assign_ahead(self):
        # Is the name we just read immediately followed by "=" / "," (an assignment target)?
        return self.tok[0] in ("=", ",")

    def suffixed_expr(self, lhs=False):
        val = self.primary_expr(lhs)
        while True:
            kind, value, line = self.tok
            if kind == ".":
                self.next()
                name = self.expect("name")[1]
                if val.global_lib in LIBS and name not in LIBS[val.global_lib]:
                    self.error(line, f"'{val.global_lib}.{name}' doesn't exist")
                if val.global_lib == "Enum":
                    val = Val(index_of=val, key=name, lvalue="field", string=("Enum", name))
                    continue
                if isinstance(val.string, tuple) and val.string[0] == "Enum":
                    enum = val.string[1]
                    if self.api:
                        if enum not in self.api.enums:
                            self.error(line, f"unknown enum 'Enum.{enum}'")
                        elif name not in self.api.enums[enum]:
                            self.error(line, f"'Enum.{enum}.{name}' doesn't exist")
                    val = Val()
                    continue
                cls = None
                if val.cls and self.api:
                    m = self.api.member(val.cls, name)
                    if m and m["MemberType"] == "Property" and m["ValueType"]["Category"] == "Class":
                        cls = m["ValueType"]["Name"]
                val = Val(index_of=val, key=name, lvalue="field", cls=cls)
            elif kind == "[":
                self.next()
                self.expr()
                self.expect("]")
                val = Val(lvalue="index")
            elif kind == ":":
                self.next()
                name = self.expect("name")[1]
                if val.cls:
                    self.check_method(val.cls, name, line)
                args = self.call_args()
                cls = None
                if name == "GetService" and args and isinstance(args[0].string, str):
                    cls = args[0].string
                    self.check_class(cls, line, service=True)
                elif name in ("FindFirstChildOfClass", "FindFirstAncestorOfClass", "FindFirstChildWhichIsA") \
                        and args and isinstance(args[0].string, str):
                    cls = args[0].string
                val = Val(call=True, cls=cls)
            elif kind in ("(", "string", "{"):
                fn = val
                args = self.call_args()
                cls = None
                if fn.lvalue == "field" and fn.index_of is not None and fn.index_of.global_lib == "Instance" \
                        and fn.key == "new" and args and isinstance(args[0].string, str):
                    cls = args[0].string
                    self.check_class(cls, line)
                elif fn.lvalue == "name" and fn.key in CREATE_FUNCS and args:
                    cls_at, props_at = CREATE_FUNCS[fn.key]
                    if isinstance(cls_at, str):
                        cls = cls_at
                    else:
                        cls = args[cls_at].string if cls_at < len(args) else None
                    props = args[props_at] if props_at < len(args) else None
                    if isinstance(cls, str):
                        self.check_class(cls, line)
                        for key, kline in (props.table_keys or []) if props else []:
                            self.check_prop_write(cls, key, kline)
                    else:
                        cls = None
                elif fn.lvalue == "name" and fn.key in CLASS_FUNCS and len(args) > CLASS_FUNCS[fn.key] \
                        and isinstance(args[CLASS_FUNCS[fn.key]].string, str):
                    cls = args[CLASS_FUNCS[fn.key]].string
                    self.check_class(cls, line)
                val = Val(call=True, cls=cls)
            else:
                return val

    def call_args(self):
        kind, value, line = self.tok
        if kind == "string":
            self.next()
            return [Val(string=value)]
        if kind == "{":
            return [self.table()]
        self.expect("(")
        args = []
        if not self.check(")"):
            args = self.explist()
        self.expect(")")
        return args

    def table(self):
        self.expect("{")
        keys = []
        while not self.check("}"):
            if self.check("["):
                self.next()
                self.expr()
                self.expect("]")
                self.expect("=")
                self.expr()
            elif self.check("name") and self.peek()[0] == "=":
                t = self.next()
                keys.append((t[1], t[2]))
                self.next()
                self.expr()
            else:
                self.expr()
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}", "'}' to close table")
        return Val(table_keys=keys)

    def simple_expr(self):
        kind, value, line = self.tok
        if kind == "number":
            self.next()
            return Val()
        if kind == "string":
            self.next()
            return Val(string=value)
        if kind in ("nil", "true", "false", "..."):
            self.next()
            return Val()
        if kind == "{":
            return self.table()
        if kind == "function":
            self.next()
            self.funcbody(line, False)
            return Val()
        if kind == "if":
            self.next()
            self.expr()
            self.expect("then")
            self.expr()
            while self.accept("elseif"):
                self.expr()
                self.expect("then")
                self.expr()
            self.expect("else", "'else' (if-expressions need one)")
            self.expr()
            return Val()
        return self.suffixed_expr()

    def expr(self, limit=0):
        kind = self.tok[0]
        if kind in ("not", "-", "#"):
            self.next()
            self.expr(UNARY_PRIORITY)
            val = Val()
        else:
            val = self.simple_expr()
        while self.tok[0] in BINARY_PRIORITY and BINARY_PRIORITY[self.tok[0]][0] > limit:
            op = self.next()[0]
            self.expr(BINARY_PRIORITY[op][1])
            val = Val()
        return val


# --------------------------------------------------------------------------- main

def main(argv):
    api_path = None
    targets = []
    it = iter(argv)
    for arg in it:
        if arg == "--api":
            api_path = next(it)
        else:
            targets.append(arg)
    api = Api(api_path) if api_path else None
    files = []
    for t in targets or ["src"]:
        p = Path(t)
        files += sorted(p.rglob("*.luau")) if p.is_dir() else [p]

    counts = {"error": 0, "warning": 0}

    def report(level, path, line, msg):
        counts[level] += 1
        print(f"{path}:{line}: {level}: {msg}")

    for f in files:
        try:
            Parser(lex(f.read_text(), f), f, api, report).chunk()
        except CheckError as e:
            counts["error"] += 1
            print(f"{e}  [syntax]")
    print(f"{len(files)} files, {counts['error']} errors, {counts['warning']} warnings")
    return 1 if counts["error"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
