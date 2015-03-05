/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
module analyzer;

import std.ascii;
import std.array;
import std.conv;
import std.stdio;
import std.string;
import std.typecons;
import std.experimental.logger;
alias logger = std.experimental.logger;

import tested;

import clang.c.index;
import clang.Index;
import clang.TranslationUnit;
import clang.Visitor;
import clang.Cursor;
import clang.UnsavedFile;

import srcgen.cpp;

import translator.Type;

version (unittest) {
    shared static this() {
        import std.exception;
        enforce(runUnitTests!analyzer(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

// Holds the context of the file.
class Context {
    /// Initialize context from file
    this(string input_file) {
        this.input_file = input_file;
        this.index = Index(false, false);
        this.translation_unit = TranslationUnit.parse(this.index, this.input_file, this.args);
    }

    ~this() {
        translation_unit.dispose;
        index.dispose;
    }

private:
    static string[] args = ["-xc++"];
    string input_file;
    Index index;
    TranslationUnit translation_unit;
}

// No errors occured during translation.
bool isValid(Context context) {
    return context.translation_unit.isValid;
}

// Print diagnostic error messages.
void diagnostic(Context context) {
    if (!context.isValid())
        return;

    auto dia = context.translation_unit.diagnostics;
    if (dia.length > 0) {
        bool translate = true;
        foreach (diag ; dia)
        {
            auto severity = diag.severity;

            with (CXDiagnosticSeverity)
                if (translate)
                    translate = !(severity == CXDiagnostic_Error || severity == CXDiagnostic_Fatal);
            writeln(stderr, diag.format);
        }
    }
}

// If apply returns true visit_ast will decend into the node if it contains children.
void visit_ast(VisitorType)(ref Cursor cursor, ref VisitorType v) {
    v.incr();
    bool decend = v.apply(cursor);

    if (!cursor.isEmpty && decend) {
        foreach (child, parent; Visitor(cursor)) {
            visit_ast(child, v);
        }
    }
    v.decr();
}

void log_node(int line = __LINE__, string file = __FILE__, string funcName = __FUNCTION__, string prettyFuncName = __PRETTY_FUNCTION__, string moduleName = __MODULE__)(ref Cursor c, int level) {
    auto indent_str = new char[level*2];
    foreach (ref ch ; indent_str) ch = ' ';

    logf!(line, file, funcName, prettyFuncName, moduleName)(
         "%s|%s [%s %s line=%d, col=%d, def=%d]",
         indent_str,
         c.spelling,
         c.kind,
         c.type,
         c.location.spelling.line,
         c.location.spelling.column,
         c.isDefinition);
}

/// T is module type.
mixin template VisitNodeModule(Tmodule) {
    alias Entry = Tuple!(Tmodule, "node", int, "level");
    Entry[] stack; // stack of cpp nodes
    int level;

    void incr() {
        level++;
        //logger.log(level, " ", stack.length);
    }

    void decr() {
        // remove node leaving the level
        if (stack.length > 1 && stack[$-1].level == level) {
            //logger.log(cast(void*)(stack[$-1].node), " ", to!string(stack[$-1]), level);
            stack.length = stack.length - 1;
        }
        level--;
    }

    ref Tmodule current() {
        //if (stack.length > 0)
        //    logger.log(cast(void*)(stack[$-1].node), " ", to!string(stack[$-1]));
        return stack[$-1].node;
    }

    T push(T)(T c) {
        stack ~= Entry(cast(Tmodule)(c), level);
        //if (stack.length > 0)
        //    logger.log(cast(void*)(stack[$-1].node), " ", to!string(stack[$-1]));
        return c;
    }
}

struct TranslateContext {
    private int indent = 0;
    private string output_;

    void incr() {
        this.indent += 1;
    }

    void decr() {
        this.indent -= 1;
    }

    bool apply(Cursor c) {
        log_node(c, this.indent);
        bool decend = true;

        with (CXCursorKind) {
            switch (c.kind) {
                case CXCursor_ClassDecl:
                    if (c.isDefinition)
                        output_ ~= (ClassTranslatorHdr(c)).translate;
                    decend = false;
                    break;

                //case CXCursor_StructDecl:
                //    if (cursor.isDefinition)
                //        output.structs ~= code;
                //    break;
                //case CXCursor_EnumDecl: output.enums ~= code; break;
                //case CXCursor_UnionDecl: output.unions ~= code; break;
                //case CXCursor_VarDecl: output.variables ~= code; break;
                //case CXCursor_FunctionDecl: output.functions ~= code; break;
                //case CXCursor_TypedefDecl: output.typedefs ~= code; break;
                default: break;
            }
        }

        return decend;
    }

    @property string output() {
        return this.output_;
    }
}

struct ClassTranslatorHdr {
    mixin VisitNodeModule!CppModule;

    private CXCursor cursor;
    private CppModule top; // top code generator node

    this(CXCursor cursor) {
        this.cursor = cursor;
        top = new CppModule;
        push(top);
    }

    this(Cursor cursor) {
        this.cursor = cursor.cx;
        top = new CppModule;
        push(top);
    }

    string translate() {
        auto c = Cursor(this.cursor);
        visit_ast!ClassTranslatorHdr(c, this);

        return top.render;
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(c, level);
        with (CXCursorKind) {
            switch (c.kind) {
                case CXCursor_ClassDecl:
                    with(current) {
                        push(class_(c.spelling));
                        sep();
                    }
                    break;
                case CXCursor_Constructor:
                    push(CtorTranslator!CppModule(c, current));
                    current[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
                    descend = false;
                    break;
                case CXCursor_CXXMethod:
                    break;
                case CXCursor_CXXAccessSpecifier:
                    push(AccessSpecifierTranslator!CppModule(c, current));
                    break;

                default: break;
            }
        }
        return descend;
    }
}

/** Translate an access specifier to code suitable for a c++ header.
 * @param cursor Cursor to translate
 * @param top Top module to append the translation to.
 */
T AccessSpecifierTranslator(T)(Cursor cursor, ref T top) {
    T node;

    with (CXCursorKind) {
        final switch (cursor.access.accessSpecifier) {
            with(CX_CXXAccessSpecifier) {
                case CX_CXXInvalidAccessSpecifier:
                    logger.log(cursor.access.accessSpecifier); break;
                case CX_CXXPublic:
                    node = top.public_;
                    break;
                case CX_CXXProtected:
                    node = top.protected_;
                    break;
                case CX_CXXPrivate:
                    node = top.private_;
                    break;
            }
        }
    }

    node.suppress_indent(1);
    return node;
}

T CtorTranslator(T)(Cursor c, ref T top) {
    T node;

    switch(c.kind) {
        case CXCursorKind.CXCursor_Constructor:
            auto params = ParmDeclToString(c);
            if (params.length == 0)
                node = top.ctor(c.spelling);
            else
                node = top.ctor(c.spelling, join(params, ","));
            break;
        default: break;
    }

    return node;
}

/** Travers a node tree and gather all paramdecl converting them to a string.
 * Example: class Simple{ Simple(char x, char y); }
 * The AST for the above is kind of the following:
 * Simple [CXCursor_Constructor Type(CXType(CXType_FunctionProto
 *   x [CXCursor_ParmDecl Type(CXType(CXType_Char_S
 *   y [CXCursor_ParmDecl Type(CXType(CXType_Char_S
 * It is translated to the string "char x, char y".
 */
string[] ParmDeclToString(Cursor cursor) {
    string[] params;

    foreach (param; cursor.func.parameters) {
        log_node(param, 0);
        auto type = translateType(param.type);
        params ~= format("%s %s", type, param.spelling);
    }

    logger.log(params);
    return params;
}

@name("Test creating a Context instance")
unittest {
    auto x = new Context("test_files/arrays.h");
}

@name("Test diagnostic on a Context, file exist")
unittest {
    auto x = new Context("test_files/arrays.h");
    x.diagnostic();
}

@name("Test diagnostic on a Context, no file")
unittest {
    auto x = new Context("foobarfailnofile.h");
    x.diagnostic();
}

@name("Test visit_ast with VisitorFoo")
unittest {
    struct VisitorFoo {
        public int count;
        private int indent;

        void incr() {
            this.indent += 1;
        }

        void decr() {
            this.indent -= 1;
        }

        bool apply(ref Cursor c) {
            log_node(c, this.indent);
            count++;
            return true;
        }
    }

    auto x = new Context("test_files/class.h");
    x.diagnostic();

    VisitorFoo v;
    auto c = x.translation_unit.cursor;
    visit_ast!VisitorFoo(c, v);
    assert(v.count == 40);
}

@name("Test of TranslateContext")
unittest {
    auto x = new Context("test_files/class.h");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output.length > 0);
}

@name("Test of ClassTranslatorHdr, class_simple.hpp")
unittest {
    auto x = new Context("test_files/class_simple.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}

@name("Test of ClassTranslatorHdr, class_nested.hpp")
unittest {
    auto x = new Context("test_files/class_nested.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}

@name("Test of ClassTranslatorHdr, class_impl.hpp")
unittest {
    auto x = new Context("test_files/class_impl.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}

@name("Test of ClassTranslatorHdr, class_simple2.hpp")
unittest {
    auto x = new Context("test_files/class_simple2.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}