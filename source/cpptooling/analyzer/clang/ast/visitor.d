/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Visitor pattern for the exposed AST from clang.

The design choice when implementing mixinNodes and mixinVisitor was between
specifically list the enumerations or use a range.
Specifically listing was chosen because:
 - Easy removal of autogenerated nodes to allow manual implementation.
   Alias this of a Cursor is a lazy, quick solution. The appropriate is...
   something else. Maybe use the knowledge for what type of cursor it is to
   restrict the operations to those appropriate.
 - Compared to a range it is easy to skip nodes.
*/
module cpptooling.analyzer.clang.ast.visitor;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

version (unittest) {
    import std.algorithm : map, splitter;
    import std.array : array;
    import std.string : strip;
    import unit_threaded : Name, shouldEqual;
    import test.helpers : shouldEqualPretty;
} else {
    struct Name {
        string name_;
    }
}

enum CXCursorKind_PrefixLen = "CXCursor_".length;

private template generateVisitRecursive(alias Base, E...) {
    import std.format : format;

    static if (E.length > 1) {
        enum generateVisitRecursive = generateVisitRecursive!(Base, E[0]) ~ generateVisitRecursive!(Base,
                    E[1 .. $]);
    } else {
        enum e_str = E[0].stringof[CXCursorKind_PrefixLen .. $];
        enum generateVisitRecursive = format(q{
                void visit(const(%s) value) {
                    visit(cast(const(%s)) value);
                }
                }, e_str, Base.stringof);
    }
}

private template generateVisit(alias Base, E...) {
    import std.format : format;

    enum visit_method = format(q{
        void visit(const(%s)) {}
    }, Base.stringof);

    enum generateVisit = visit_method ~ generateVisitRecursive!(Base, E);
}

@Name("Should be the mixin string of declarations in CXCursorKind")
unittest {
    class Declaration {
    }

    // dfmt off
    generateVisit!(Declaration, CXCursorKind.CXCursor_UnexposedDecl,
                   CXCursorKind.CXCursor_UnionDecl)
        .splitter('\n')
        .map!(a => a.strip)
        .array()
        .shouldEqualPretty([
                     "",
                     "void visit(const(Declaration)) {}",
                     "",
                     "void visit(const(UnexposedDecl) value) {",
                     "visit(cast(const(Declaration)) value);",
                     "}",
                     "",
                     "void visit(const(UnionDecl) value) {",
                     "visit(cast(const(Declaration)) value);",
                     "}",
                     ""
                     ]);
    // dfmt on
}

abstract class Visitor {
    import cpptooling.analyzer.clang.ast;

@safe:
    mixin(generateVisit!(Attribute, AttributeSeq));
    mixin(generateVisit!(Declaration, DeclarationSeq));
    mixin(generateVisit!(Directive, DirectiveSeq));
    mixin(generateVisit!(Expression, ExpressionSeq));
    mixin(generateVisit!(Preprocessor, PreprocessorSeq));
    mixin(generateVisit!(Reference, ReferenceSeq));
    mixin(generateVisit!(Statement, StatementSeq));

    void visit(const TranslationUnit) {
    }

    /// Called when entering a node
    void incr() {
    }

    /// Called when leaving a node
    void decr() {
    }
}

@Name("Should be an instane of a Visitor")
unittest {
    class V2 : Visitor {
    }

    auto v = new V2;
}