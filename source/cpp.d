/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
import std.algorithm;
import std.ascii;
import std.conv;
import std.stdio;
import std.string;
import std.typetuple;

import std.experimental.logger;
alias logger = std.experimental.logger;

import tested;

shared static this() {
    version (unittest) {
        import core.runtime;
        Runtime.moduleUnitTester = () => true;
        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        assert(runUnitTests!cpp(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

struct KV {
    string k;
    string v;

    this(T)(string k, T v) {
        this.k = k;
        this.v = to!string(v);
    }
}

struct AttrSetter {
    static AttrSetter instance;

    template opDispatch(string name) {
        @property auto opDispatch(T)(T v) {
            static if(name.length > 1 && name[$-1] == '_') {
                return KV(name[0 .. $-1], v);
            }
            else {
                return KV(name, v);
            }
        }
    }
}

interface BaseElement {
    abstract string render();
    abstract string _render_indent(int level);
    abstract string _render_recursive(int level);
    abstract string _render_post_recursive(int level);
}

class BaseModule : BaseElement {
    static int indent_width = 4;

    BaseElement[] children;
    int sep_lines;
    int suppress_indent_;

    this() {}

    this(int indent_width) {
        this.indent_width = indent_width;
    }

    /// Number of levels to suppress indent
    void suppress_indent(int levels) {
        this.suppress_indent_ = levels;
    }

    auto reset() {
        children.length = 0;
        return this;
    }

    /// Separate with at most count empty lines.
    void sep(int count = 1) {
        count -= sep_lines;
        if (count <= 0)
            return;
        foreach(i; 0 .. count) {
            children ~= new Text(newline);
        }

        sep_lines += count;
    }

    string indent(string s, int level) {
        level = max(0, level);
        char[] indent;
        indent.length = indent_width*level;
        indent[] = ' ';

        return to!string(indent) ~ s;
    }

    void _append(BaseElement e) {
        children ~= e;
        sep_lines = 0;
    }

    override string _render_indent(int level) {
        return "";
    }

    override string _render_recursive(int level) {
        level -= suppress_indent_;
        string s = _render_indent(level);

        foreach(e; children) {
            s ~= e._render_recursive(level+1);
        }
        s ~= _render_post_recursive(level);

        return s;
    }

    override string _render_post_recursive(int level) {
        return "";
    }

    override string render() {
        string s = _render_indent(0);
        foreach(e; children) {
            s ~= e._render_recursive(0 - suppress_indent_);
        }
        s ~= _render_post_recursive(0);

        return _render_recursive(0);
    }
}

class Text: BaseModule {
    string contents;
    this(string contents) {
        this.contents = contents;
    }

    override string _render_indent(int level) {
        return contents;
    }
}

class Comment: BaseModule {
    string contents;
    this(string contents) {
        this.contents = contents;
        sep();
    }

    override string _render_indent(int level) {
        return indent("// " ~ contents, level);
    }
}

class CppModule: BaseModule {
    string[string] attrs;

    @property auto _() {
        return this;
    }

    auto opIndex(T...)(T kvs) {
        foreach(kv; kvs) {
            attrs[kv.k] = kv.v;
        }
        return this;
    }

    auto opDollar(int dim)() {
        return AttrSetter.instance;
    }

    auto text(T)(T content) {
        auto e = new Text(to!string(content));
        _append(e);
        return this;
    }
    alias opCall = text;

    auto comment(string comment) {
        auto e = new Comment(comment);
        _append(e);
        return this;
    }

    auto base() {
        auto e = new CppModule;
        _append(e);
        return e;
    }

    // Statements
    auto stmt(T)(T stmt_) {
        auto e = new CppStmt(to!string(stmt_));
        _append(e);
        sep();
        return e;
    }

    auto break_() {
        return stmt("break");
    }

    auto continue_() {
        return stmt("continue");
    }

    auto return_(T)(T expr) {
        return stmt(format("return %s", to!string(expr)));
    }

    auto goto_(string name) {
        return stmt(format("goto %s", name));
    }

    auto label(string name) {
        return stmt(format("%s:", name));
    }

    auto define(string name) {
        auto e = stmt(format("#define %s", name));
        e[$.end = ""];
        return e;
    }

    auto define(T)(string name, T value) {
        // may need to replace \n with \\\n
        auto e = stmt(format("#define %s %s", name, to!string(value)));
        e[$.end = ""];
        return e;
    }

    // Suites
    auto suite(T)(T headline) {
        auto e = new CppSuite(to!string(headline));
        _append(e);
        return e;
    }

    auto if_(T)(T cond) {
        return suite(format("if (%s)", cond));
    }

    auto else_if(T)(T cond) {
        return suite(format("else if (%s)", cond));
    }

    auto else_() {
        return suite("else");
    }

    auto for_(T0, T1, T2)(T0 init, T1 cond, T2 next) {
        return suite(format("for (%s; %s; %s)",
                            to!string(init),
                            to!string(cond),
                            to!string(next)));
    }

    auto while_(T)(T cond) {
        return suite(format("while (%s)", to!string(cond)));
    }

    auto do_while(T)(T cond) {
        auto e = suite("do");
        e[$.end = format("} while (%s);%s", to!string(cond), newline)];
        return e;
    }

    auto switch_(T)(T cond) {
        return suite(format("switch (%s)", to!string(cond)));
    }

    auto case_(T)(T val) {
        auto e = suite(format("case %s:", to!string(val)));
        e[$.begin = newline, $.end = ""];
        return e;
    }

    auto default_() {
        auto e = suite("default:");
        e[$.begin = newline, $.end = ""];
        return e;
    }

    auto func(T0, T1, T...)(T0 return_type, T1 name, auto ref T args) {
        string params;
        if (args.length >= 1) {
            params = to!string(args[0]);
        }
        if (args.length >= 2) {
            foreach(v; args[1 .. $]) {
                params ~= ", " ~ to!string(v);
            }
        }

        auto e = suite(format("%s %s(%s)",
                              to!string(return_type),
                              to!string(name),
                              params));
        return e;
    }

    auto IF(T)(T name) {
        auto e = suite(format("#if %s", to!string(name)));
        e[$.begin = newline, $.end = format("#endif // %s%s", name, newline)];
        return e;
    }

    auto IFDEF(T)(T name) {
        auto e = suite(format("#ifdef %s", to!string(name)));
        e[$.begin = newline, $.end = format("#endif // %s%s", name, newline)];
        return e;
    }

    auto IFNDEF(T)(T name) {
        auto e = suite(format("#ifndef %s", to!string(name)));
        e[$.begin = newline, $.end = format("#endif // %s%s", name, newline)];
        return e;
    }

    auto ELIF(T)(T cond) {
        return stmt(format("#elif %s", to!string(cond)));
    }

    auto ELSE(T)(T cond) {
        return stmt(format("#else %s", to!string(cond)));
    }
}

@name("Test of statements")
unittest {
    string expect = """    77;
    break;
    continue;
    return 5;
    return long_value;
    goto foo;
    bar:
    #define foobar
    #define smurf 1
""";

    auto x = new CppModule();

    with (x) {
        stmt(77);
        break_;
        continue_;
        return_(5);
        return_("long_value");
        goto_("foo");
        label("bar");
        define("foobar");
        define("smurf", 1);
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}

@name("Test of suites")
unittest {
    string expect = """
    foo {
    }
    if (foo) {
    }
    else if (bar) {
    }
    else {
    }
    for (x; y; z) {
    }
    while (x) {
    }
    do {
    } while (x);
    switch (x) {
    }
    case y:
        foo;
    default:
        foobar;
    int foobar(x) {
    }
""";

    auto x = new CppModule();
    with (x) {
        sep();
        suite("foo");
        if_("foo");
        else_if("bar");
        else_;
        for_("x", "y", "z");
        while_("x");
        do_while("x");
        switch_("x");
        with(case_("y")) {
            stmt("foo");
        }
        with(default_) {
            stmt("foobar");
        }
        func("int", "foobar", "x");
    }

    auto rval = x.render;
    assert(rval == expect, rval);
}
@name("Test of complicated switch")
unittest {
    string expect = """
    switch (x) {
        case 0:
            return 5;
            break;
        case 1:
            return 3;
            break;
        default:
            return -1;
    }
""";

    auto x = new CppModule();
    with (x) {
        sep();
        with(switch_("x")) {
            with(case_(0)) {
                return_(5);
                break_;
            }
            with(case_(1)) {
                return_(3);
                break_;
            }
            with(default_) {
                return_(-1);
            }
        }
    }

    auto rval = x.render;
    assert(rval == expect, rval);
}

string stmt_append_end(string s, in ref string[string] attrs) pure nothrow @safe {
    bool in_pattern = false;
    try {
        in_pattern = inPattern(s[$-1], ";:,{");
    } catch (Exception e) {}

    if (!in_pattern && s[0] != '#') {
        string end = ";";
        if ("end" in attrs) {
            end = attrs["end"];
        }
        s ~= end;
    }

    return s;
}

@name("Test of stmt_append_end")
unittest {
    string[string] attrs;
    string stmt = "some_line";
    string result = stmt_append_end(stmt, attrs);
    assert(stmt ~ ";" == result, result);

    result = stmt_append_end(stmt ~ ";", attrs);
    assert(stmt ~ ";" == result, result);

    attrs["end"] = "{";
    result = stmt_append_end(stmt, attrs);
    assert(stmt ~ "{" == result, result);
}

class CppStmt : CppModule {
    string stmt;

    this(string stmt) {
        this.stmt = stmt;
    }

    override string _render_indent(int level) {
        string s = stmt_append_end(stmt, attrs);
        return indent(s, level);
    }
}

class CppSuite : CppModule {
    string headline;

    this(string headline) {
        this.headline = headline;
    }

    override string _render_indent(int level) {
        string r = headline ~ " {" ~ newline;
        if ("begin" in attrs) {
            r = headline ~ attrs["begin"];
        }
        if (r.length > 0) {
            r = indent(r, level);
        }
        return r;
    }

    override string _render_post_recursive(int level) {
        string r = "}" ~ newline;
        if ("end" in attrs) {
            r = attrs["end"];
        }
        if (r.length > 0) {
            r = indent(r, level);
        }
        return r;
    }
}

@name("Test of empty CppSuite")
unittest {
    auto x = new CppSuite("test");
    assert(x.render == "test {\n}\n", x.render);
}

@name("Test of CppSuite with formatting")
unittest {
    auto x = new CppSuite("if (x > 5)");
    assert(x.render() == "if (x > 5) {\n}\n", x.render);
}

@name("Test of CppSuite with simple text")
unittest {
    // also test that text(..) do NOT add a linebreak
    auto x = new CppSuite("foo");
    with (x) {
        text("bar");
    }
    assert(x.render() == "foo {\nbar}\n", x.render);
}

@name("Test of CppSuite with simple text and changed begin")
unittest {
    auto x = new CppSuite("foo");
    with (x[$.begin = "_:_"]) {
        text("bar");
    }
    assert(x.render() == "foo_:_bar}\n", x.render);
}

@name("Test of CppSuite with simple text and changed end")
unittest {
    auto x = new CppSuite("foo");
    with (x[$.end = "_:_"]) {
        text("bar");
    }
    assert(x.render() == "foo {\nbar_:_", x.render);
}

@name("Test of nested CppSuite")
unittest {
    auto x = new CppSuite("foo");
    with (x) {
        text("bar");
        sep();
        with (suite("smurf")) {
            comment("bar");
        }
    }
    assert(x.render() == """foo {
bar
    smurf {
        // bar
    }
}
""", x.render);
}

/// Code generation for C++ header.
struct CppHModule {
    string ifdef_guard;
    CppModule doc;
    CppModule header;
    CppModule content;
    CppModule footer;

    this(string ifdef_guard) {
        // Must suppress indentation to generate what is expected by the user.
        this.ifdef_guard = ifdef_guard;
        doc = new CppModule;
        with (doc) {
            suppress_indent(1);
            header = base;
            header.suppress_indent(1);
            with (IFNDEF(ifdef_guard)) {
                suppress_indent(1);
                define(ifdef_guard);
                content = base;
                content.suppress_indent(1);
            }
            footer = base;
            footer.suppress_indent(1);
        }
    }

    auto render() {
        return doc.render();
    }
}

@name("Test of text in CppModule with guard")
unittest {
    auto hdr = CppHModule("somefile_hpp");

    with (hdr.header) {
        text("header text");
        sep();
        comment("header comment");
    }
    with (hdr.content) {
        text("content text");
        sep();
        comment("content comment");
    }
    with (hdr.footer) {
        text("footer text");
        sep();
        comment("footer comment");
    }

    assert(hdr.render == """header text
// header comment
#ifndef somefile_hpp
#define somefile_hpp
content text
// content comment
#endif // somefile_hpp
footer text
// footer comment
""", hdr.render);
}
