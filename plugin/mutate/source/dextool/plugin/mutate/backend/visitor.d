/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.visitor;

public import dextool.clang_extensions : ValueKind;
import logger = std.experimental.logger;

import cpptooling.analyzer.clang.ast : Visitor;
import dextool.type : AbsolutePath;

@safe:

/** Find all mutation points that affect a whole expression.
 *
 * TODO change the name of the class. It is more than just an expression
 * visitor.
 */
final class ExpressionVisitor : Visitor {
    import std.array : Appender;
    import clang.Cursor : Cursor;
    import clang.SourceLocation : SourceLocation;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;
    import dextool.clang_extensions;
    import dextool.type : AbsolutePath, FileName;
    import dextool.plugin.mutate.backend.type : MutationPoint;
    import dextool.plugin.mutate.backend.database : MutationPointEntry;
    import dextool.plugin.mutate.backend.interface_ : ValidateLoc;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    private Appender!(MutationPointEntry[]) exprs;
    private bool[string] files;
    private ValidateLoc val_loc;

    const(MutationPointEntry[]) mutationPoints() {
        return exprs.data;
    }

    string[] mutationPointFiles() @trusted {
        import std.array : array;

        return files.byKey.array();
    }

    /**
     * Params:
     *  restrict = only analyze files starting with this path
     */
    this(ValidateLoc val_loc) nothrow {
        this.val_loc = val_loc;
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Attribute) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Directive) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());

        if (!val_loc.shouldAnalyze(v.cursor.location.path)) {
            return;
        }

        addExprMutationPoint(getExprOperator(v.cursor));

        v.accept(this);
    }

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());
        unaryNode(v);
    }

    override void visit(const IntegerLiteral v) {
        mixin(mixinNodeLog!());
        unaryNode(v);
    }

    void unaryNode(T)(const T v) {
        auto loc = v.cursor.location;

        if (!val_loc.shouldAnalyze(loc.path)) {
            return;
        }

        // it is NOT an operator.
        addMutationPoint(v.cursor);
        addExprMutationPoint(getExprOperator(v.cursor));

        v.accept(this);
    }

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());

        auto loc = v.cursor.location;
        if (!val_loc.shouldAnalyze(loc.path)) {
            return;
        }

        addStatement(v);

        auto op = getExprOperator(v.cursor);
        if (op.isValid) {
            addExprMutationPoint(op);
            auto s = op.sides;
            addMutationPoint(s.lhs);
            addMutationPoint(s.rhs);
        }

        v.accept(this);
    }

    override void visit(const(BinaryOperator) v) {
        mixin(mixinNodeLog!());

        auto loc = v.cursor.location;
        if (!val_loc.shouldAnalyze(loc.path)) {
            return;
        }

        auto op = getExprOperator(v.cursor);
        if (op.isValid) {
            addExprMutationPoint(op);
            auto s = op.sides;
            addMutationPoint(s.lhs);
            addMutationPoint(s.rhs);
        }

        v.accept(this);
    }

    override void visit(const(CompoundAssignOperator) v) {
        mixin(mixinNodeLog!());
        import std.range : dropOne;
        import cpptooling.analyzer.clang.ast.tree : dispatch;

        auto loc = v.cursor.location;
        if (!val_loc.shouldAnalyze(loc.path)) {
            return;
        }

        // not adding the left side because it results in nonsense mutations for UOI.
        foreach (child; v.cursor.children.dropOne) {
            dispatch(child, this);
        }
    }

    // TODO ugly duplication between this and addExprMutationPoint. Fix it.
    void addMutationPoint(const(Cursor) c) {
        import std.algorithm : map;
        import std.array : array;
        import std.range : chain;
        import dextool.plugin.mutate.backend.type : Offset;
        import dextool.plugin.mutate.backend.utility;

        if (!c.isValid)
            return;

        const auto kind = exprValueKind(getUnderlyingExprNode(c));

        SourceLocation loc = c.location;

        // a bug in getExprOperator makes the path for a ++ which is overloaded
        // is null.
        string path = loc.path;
        if (path is null)
            return;
        files[path] = true;

        auto sr = c.extent;
        auto offs = Offset(sr.start.offset, sr.end.offset);

        auto m0 = absMutations;
        auto m1 = kind == ValueKind.lvalue ? uoiLvalueMutations : uoiRvalueMutations;
        auto m = chain(m0, m1).map!(a => Mutation(a)).array();
        auto p2 = MutationPointEntry(MutationPoint(offs, m), AbsolutePath(FileName(path)));
        exprs.put(p2);
    }

    void addExprMutationPoint(const(Operator) op) {
        import std.algorithm : map;
        import std.array : array;
        import std.range : chain;
        import dextool.plugin.mutate.backend.type : Offset;
        import dextool.plugin.mutate.backend.utility;

        if (!op.isValid)
            return;

        SourceLocation loc = op.cursor.location;
        // a bug in getExprOperator makes the path for a ++ which is overloaded
        // is null.
        auto path = loc.path;
        if (path is null)
            return;
        files[path] = true;

        auto sr = op.location.spelling;
        auto offs = Offset(sr.offset, cast(uint)(sr.offset + op.length));

        Mutation[] m;

        if (auto v = op.kind in isRor)
            m = rorMutations(*v).map!(a => Mutation(a)).array();
        else if (auto v = op.kind in isLcr)
            m = lcrMutations(*v).map!(a => Mutation(a)).array();
        else if (auto v = op.kind in isAor)
            m = aorMutations(*v).map!(a => Mutation(a)).array();
        else if (auto v = op.kind in isAorAssign)
            m = aorAssignMutations(*v).map!(a => Mutation(a)).array();

        if (m.length != 0)
            exprs.put(MutationPointEntry(MutationPoint(offs, m), AbsolutePath(FileName(path))));
    }

    override void visit(const(Preprocessor) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Reference) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        addStatement(v);
        v.accept(this);
    }

    void addStatement(T)(const(T) v) {
        import std.algorithm : map;
        import std.array : array;
        import dextool.plugin.mutate.backend.type : Offset;
        import dextool.plugin.mutate.backend.utility;

        auto loc = v.cursor.location;
        if (!val_loc.shouldAnalyze(loc.path)) {
            return;
        }

        auto path = loc.path;
        if (path is null)
            return;
        files[path] = true;

        auto offs = calcOffset(v);
        auto m = stmtDelMutations.map!(a => Mutation(a)).array();

        exprs.put(MutationPointEntry(MutationPoint(offs, m), AbsolutePath(FileName(path))));
    }
}

private:

import dextool.plugin.mutate.backend.type : Offset;

// trusted: the tokens do not escape this function.
Offset calcOffset(T)(const(T) v) @trusted {
    import clang.c.Index : CXTokenKind;
    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.cursor_logger : logNode, mixinNodeLog;

    Offset rval;

    static if (is(T == CallExpr)) {
        import clang.Token;

        auto sr = v.cursor.extent;
        rval = Offset(sr.start.offset, sr.end.offset);

        // TODO this is extremly inefficient. change to a more localized cursor
        // or even better. Get the tokens at the end.
        auto arg = v.cursor.translationUnit.cursor;

        foreach (t; arg.tokens) {
            // also delete the punctuation ";" when removing a function call
            if (t.location.offset >= sr.end.offset) {
                if (t.kind == CXTokenKind.punctuation && t.spelling == ";") {
                    rval.end = t.extent.end.offset;
                }
                break;
            }
        }
    } else {
        auto sr = v.cursor.extent;
        rval = Offset(sr.start.offset, sr.end.offset);
    }

    return rval;
}
