/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutate_operator;

import logger = std.experimental.logger;
import std.typecons : Nullable;

import dextool.type : AbsolutePath, FileName, Exists;

import dextool.clang_extensions;

@safe:

// TODO merge the mutate functions.

void aorMutate(const Exists!AbsolutePath input_file, const AbsolutePath output_dir,
        const string[] cflags, const Nullable!size_t in_mutation_point) {
    auto mutator = Mutate!(opMutation!(aorOps))(&operatorFilter!(aorOps));
    mutator.run(input_file, output_dir, cflags, in_mutation_point);
}

void lcrMutate(const Exists!AbsolutePath input_file, const AbsolutePath output_dir,
        const string[] cflags, const Nullable!size_t in_mutation_point) {
    auto mutator = Mutate!(opMutation!(lcrOps))(&operatorFilter!(lcrOps));
    mutator.run(input_file, output_dir, cflags, in_mutation_point);
}

void rorMutate(const Exists!AbsolutePath input_file, const AbsolutePath output_dir,
        const string[] cflags, const Nullable!size_t in_mutation_point) {
    auto mutator = Mutate!(opMutation!(rorOps))(&operatorFilter!(rorOps));
    mutator.run(input_file, output_dir, cflags, in_mutation_point);
}

void uorMutate(const Exists!AbsolutePath input_file, const AbsolutePath output_dir,
        const string[] cflags, const Nullable!size_t in_mutation_point) {
    auto mutator = Mutate!(uorMutation)(&operatorFilter!(uorOps));
    mutator.run(input_file, output_dir, cflags, in_mutation_point);
}

private:

size_t randomMutationPoint(const Nullable!size_t point, const size_t total_mutation_points) {
    if (point.isNull) {
        return randomMutationPoint(total_mutation_points);
    } else if (point < total_mutation_points) {
        return point.get;
    } else {
        logger.infof("Mutation point %s out of range. Choosing a random point", point.get);
        return randomMutationPoint(total_mutation_points);
    }
}

size_t randomMutationPoint(const size_t total_mutation_points) nothrow {
    if (total_mutation_points == 0)
        return 0;

    try {
        import std.random : uniform;

        return uniform(0, total_mutation_points);
    }
    catch (Exception e) {
    }

    return 0;
}

struct Mutate(alias mutateFunc) {
    import dextool.plugin.mutate.backend.visitor : ExpressionOpVisitor;

    ExpressionOpVisitor.OpFilter opFilter;

    void run(const Exists!AbsolutePath input_file, const AbsolutePath output_dir,
            const string[] cflags, const Nullable!size_t in_mutation_point) {
        import std.typecons : Yes;
        import cpptooling.analyzer.clang.context : ClangContext;
        import dextool.type : ExitStatusType;
        import dextool.utility : analyzeFile;

        auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
        auto visitor = new ExpressionOpVisitor(opFilter);
        auto exit_status = analyzeFile(input_file, cflags, visitor, ctx);

        if (exit_status != ExitStatusType.Ok) {
            logger.error("Unable to mutate: ", cast(string) input_file);
            return;
        } else if (visitor.operators.length == 0) {
            logger.error("No mutation points in: ", cast(string) input_file);
            return;
        }

        logger.info("Total number of mutation points: ", visitor.operators.length);

        const size_t mut_point = randomMutationPoint(in_mutation_point, visitor.operators.length);

        logger.info("Mutation point ", mut_point);

        import dextool.plugin.mutate.backend.vfs;

        const auto op = visitor.operators[mut_point];
        auto offset = Offset(op.location.spelling.offset,
                cast(uint)(op.location.spelling.offset + op.length));

        import std.algorithm : each;
        import std.conv : to;
        import std.stdio : File;
        import std.path : buildPath, baseName;

        foreach (idx, mut; mutateFunc(op.kind)) {
            const output_file = buildPath(output_dir, idx.to!string ~ input_file.baseName);
            auto s = ctx.virtualFileSystem.drop!(void[])(input_file, offset);

            auto fout = File(output_file, "w");
            // trusted: is safe in dmd-2.077.0. Remove trusted in the future
            () @trusted{ fout.rawWrite(s.front); }();
            s.popFront;
            // trusted: is safe in dmd-2.077.0. Remove trusted in the future
            () @trusted{ fout.write(mut); fout.rawWrite(s.front); }();

            logger.infof("Mutated from '%s' to '%s' at %s", op.kind, mut, op.location);
        }
    }
}

immutable(string[OpKind]) rorOps() {
    immutable ops = [
        OpKind.LT : "<", OpKind.LE : "<=", OpKind.GT : ">", OpKind.GE : ">=",
        OpKind.EQ : "==", OpKind.NE : "!="
    ];
    return ops;
}

immutable(string[OpKind]) lcrOps() {
    immutable ops = [OpKind.LAnd : "&&", OpKind.LOr : "||"];
    return ops;
}

immutable(string[OpKind]) aorOps() {
    immutable ops = [
        OpKind.Mul : "*", OpKind.Div : "/", OpKind.Rem : "%", OpKind.Add : "+", OpKind.Sub : "-",
    ];
    return ops;
}

immutable(string[OpKind]) aorAssignOps() {
    immutable ops = [
        OpKind.MulAssign : "*=", OpKind.DivAssign : "/=", OpKind.RemAssign : "%=",
        OpKind.AddAssign : "+=", OpKind.SubAssign : "-=",
    ];
    return ops;
}

immutable(string[OpKind]) uorOps() {
    immutable ops = [
        OpKind.PostInc : "++", OpKind.PostDec : "--", OpKind.PreInc : "++", OpKind.PreDec : "--",
    ];
    return ops;
}

immutable(string[OpKind]) uorPostOps() {
    immutable ops = [OpKind.PostInc : "++", OpKind.PostDec : "--",];
    return ops;
}

immutable(string[OpKind]) uorPreOps() {
    immutable ops = [OpKind.PreInc : "++", OpKind.PreDec : "--",];
    return ops;
}

bool operatorFilter(alias ops)(OpKind kind) {
    return (kind in ops) !is null;
}

immutable(string)[] opMutation(alias ops)(dextool.clang_extensions.OpKind kind) @trusted {
    import std.algorithm;
    import std.array : array;

    return ops.byKeyValue.filter!(a => a.key != kind).map!(a => a.value).array();
}

immutable(string)[] uorMutation(dextool.clang_extensions.OpKind kind) @trusted {
    import std.algorithm;
    import std.array : array;

    if ((kind in uorPreOps) !is null) {
        return uorPreOps.byKeyValue.filter!(a => a.key != kind).map!(a => a.value).array();
    } else {
        return uorPostOps.byKeyValue.filter!(a => a.key != kind).map!(a => a.value).array();
    }
}