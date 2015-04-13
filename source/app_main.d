/// Written in the D programming language.
/// Date: 2014-2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module app_main;

import std.conv;
import std.exception;
import std.stdio;
import std.string;

import file = std.file;
import logger = std.experimental.logger;

import docopt;
import argvalue; // from docopt
import tested;
import dsrcgen.cpp;

static string doc = "
usage:
  gen-test-double stub [options] <infile> <outfile>
  gen-test-double mock [options] <infile> <outfile>

options:
 -h, --help     show this
 -d, --debug    turn on debug output for tracing of generator flow
";

class SimpleLogger : logger.Logger {
    int line = -1;
    string file = null;
    string func = null;
    string prettyFunc = null;
    string msg = null;
    logger.LogLevel lvl;

    this(const logger.LogLevel lv = logger.LogLevel.info) {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        this.line = payload.line;
        this.file = payload.file;
        this.func = payload.funcName;
        this.prettyFunc = payload.prettyFuncName;
        this.lvl = payload.logLevel;
        this.msg = payload.msg;

        stderr.writefln("%s: %s", text(this.lvl), this.msg);
    }
}

shared static this() {
    version (unittest) {
        import core.runtime;

        Runtime.moduleUnitTester = () => true;
        assert(runUnitTests!app_main(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

int gen_stub(in string infile, in string outfile) {
    import std.exception;
    import std.path : stripExtension;
    import generator;

    if (!file.exists(infile)) {
        logger.errorf("File '%s' do not exist", infile);
        return -1;
    }

    logger.infof("Generating stub from file '%s'", infile);

    auto file_ctx = new Context(infile);
    file_ctx.log_diagnostic();

    auto ctx = new StubContext(StubPrefix("Stub"));
    ctx.translate(file_ctx.cursor);

    try {
        auto open_outfile = File(outfile, "w");
        scope(exit) open_outfile.close();
        open_outfile.write(ctx.output_header(outfile));
    }
    catch (ErrnoException ex) {
        logger.trace(text(ex));
        logger.errorf("Unable to write to file '%s'", outfile);
        return -1;
    }

    return 0;
}

void prepare_env(ref ArgValue[string] parsed) {
    import std.experimental.logger.core : sharedLog;

    try {
        if (parsed["--debug"].isTrue) {
            logger.globalLogLevel(logger.LogLevel.all);
        }
        else {
            logger.globalLogLevel(logger.LogLevel.info);
            auto simple_logger = new SimpleLogger();
            logger.sharedLog(simple_logger);
        }
    }
    catch (Exception ex) {
        collectException(logger.error("Failed to configure logging level"));
        throw ex;
    }
}

int do_test_double(ref ArgValue[string] parsed) {
    int exit_status = -1;

    if (parsed["stub"].isTrue) {
        exit_status = gen_stub(parsed["<infile>"].toString, parsed["<outfile>"].toString);
    }
    else if (parsed["mock"].isTrue) {
        logger.error("Mock generation not implemented yet");
    }
    else {
        logger.error("Usage error");
        writeln(doc);
    }

    return exit_status;
}

int rmain(string[] args) nothrow {
    import std.array : join;

    string errmsg, tracemsg;
    int exit_status = -1;
    bool help = true;
    bool optionsFirst = false;
    auto version_ = "gen-test-double v0.1";

    try {
        auto parsed = docopt.docopt(doc, args[1 .. $], help, version_, optionsFirst);
        prepare_env(parsed);
        logger.trace(to!string(args));
        logger.trace(join(args, " "));
        logger.trace(prettyPrintArgs(parsed));

        exit_status = do_test_double(parsed);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = -1;
    }

    return exit_status;
}
