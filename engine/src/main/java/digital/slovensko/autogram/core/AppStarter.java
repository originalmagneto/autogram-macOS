package digital.slovensko.autogram.core;

import digital.slovensko.autogram.ui.cli.CliApp;
import digital.slovensko.autogram.ui.gui.GUIApp;
import digital.slovensko.autogram.ui.machine.MachineCliApp;
import digital.slovensko.autogram.ui.machine.v2.MachineV2CliApp;
import javafx.application.Application;
import org.apache.commons.cli.*;

import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.function.Function;

public class AppStarter {
    private static final Options options = new Options().addOptionGroup(new OptionGroup().addOption(new Option(null,
            "url", true,
            "Start in GUI mode with API server listening on given port and protocol (HTTP/HTTPS). Application starts minimised when is not empty."))
            .addOption(new Option("c", "cli", false, "Run application in CLI mode.")))
            .addOption("h", "help", false, "Print this command line help.")
            .addOption("u", "usage", false, "Print usage examples.")
            .addOption("s", "source", true, "Source file or directory of files to sign.")
            .addOption("t", "target", true,
                    "Target file or directory for signed files. Type (file/directory) must match the source.")
            .addOption("f", "force", false, "Overwrite existing file(s).")
            .addOption(null, "pdfa", false, "Check PDF/A compliance before signing.")
            .addOption(null, "parents", false, "Create all parent directories for target if needed.")
            .addOption("d", "driver", true,
                    "PCKS driver name for signing. Supported values: eid, cz_eid, secure_store, monet, gemalto, keystore, custom_pkcs11 (requires valid path within pkcs11-driver-path option).")
            .addOption(null, "key", true,
                    "Certificate serial number or common name to use without an interactive key prompt.")
            .addOption(null, "pin-stdin", false,
                    "Read the signing PIN or password from standard input without an interactive prompt.")
            .addOption(null, "list-keys", false,
                    "List available signing certificates and exit.")
            .addOption(null, "keystore", true, "Absolute path to a keystore file that can be used for signing.")
            .addOption(null, "slot-id", true,
                    "Slot ID for PKCS11 driver. If not specified, first available slot is used.")
            .addOption(null, "pdf-level", true,
                    "PDF signature level. Supported values include PAdES_BASELINE_B and PAdES_BASELINE_T.")
            .addOption(null, "en319132", false, "Sign according to EN 319 132 or EN 319 122.")
            .addOption(null, "tsa-server", true,
                    "Url of TimeStamp Authority server that should be used for timestamping in signature level BASELINE_T. If provided, BASELINE_T signatures are made.")
            .addOption(null, "plain-xml", false, "Enable signing plain (non-slovak-eform) XML files.")
            .addOption(null, "pkcs11-driver-path", true, "Absolute path to a file with custom PKCS11 driver.")
            .addOption(null, "machine-readable", false, "Run the CLI using the machine protocol.")
            .addOption(null, "protocol-version", true, "Machine protocol version.")
            .addOption(null, "operation", true, "Machine protocol operation.");

    public static void start(String[] args) {
        // macOS App Name Fix
        System.setProperty("apple.awt.application.name", "Autogram");
        System.setProperty("com.apple.mrj.application.apple.menu.about.name", "Autogram");

        try {
            CommandLine cmd = parse(args);

            if (cmd.hasOption("h")) {
                printHelp();
            } else if (cmd.hasOption("u")) {
                printUsage();
            } else if (cmd.hasOption("c")) {
                var exitCode = dispatchCli(cmd, CliApp::start, machineCommandLine -> machineCliStart(machineCommandLine));
                System.out.flush();
                System.err.flush();
                if (cmd.hasOption("machine-readable")) {
                    terminateCliProcess(exitCode);
                } else if (requiresIntelCliCleanup(cmd))
                    terminateCliProcess(exitCode);
                else
                    System.exit(exitCode);
            } else {
                Application.launch(GUIApp.class, args);
            }
        } catch (ParseException e) {
            System.err.println("Unable to parse program args");
            System.err.println(e);
        }
    }

    static CommandLine parse(String[] args) throws ParseException {
        return new DefaultParser().parse(options, args);
    }

    static int dispatchCli(CommandLine commandLine, Function<CommandLine, Integer> humanCli,
            Function<CommandLine, Integer> machineCli) {
        return commandLine.hasOption("machine-readable") ? machineCli.apply(commandLine) : humanCli.apply(commandLine);
    }

    private static int machineCliStart(CommandLine commandLine) {
        var input = new InputStreamReader(System.in, StandardCharsets.UTF_8);
        var output = new PrintWriter(System.out, true, StandardCharsets.UTF_8);
        var error = new PrintWriter(System.err, true, StandardCharsets.UTF_8);
        if ("2".equals(commandLine.getOptionValue("protocol-version"))) {
            return MachineV2CliApp.start(commandLine, input, output, error);
        }
        return MachineCliApp.start(commandLine, input, output, error);
    }

    static boolean requiresIntelCliCleanup(CommandLine commandLine) {
        return !commandLine.hasOption("machine-readable") && isIntelProcess();
    }

    private static void terminateCliProcess(int exitCode) {
        // Some PKCS#11 runtimes hang or abort during native process cleanup.
        // CLI output and files are flushed before terminating this short-lived process.
        try {
            new ProcessBuilder("/bin/kill", "-KILL", Long.toString(ProcessHandle.current().pid())).start();
            while (true)
                Thread.onSpinWait();
        } catch (java.io.IOException e) {
            Runtime.getRuntime().halt(exitCode);
        }
    }

    private static boolean isIntelProcess() {
        return "x86_64".equals(System.getProperty("os.arch"));
    }

    public static void printHelp() {
        final HelpFormatter formatter = new HelpFormatter();
        final String syntax = "autogram";
        final String footer = """

                In CLI mode, signed files are saved with the same name as the source file, but with the suffix "_signed" if no target is specified. If the source is a directory, the target must also be a directory. If the source is a file, the target must also be a file. If the source is a driectory and no target is specified, a target directory is created with the same name as the source directory, but with the suffix "_signed".

                If no target is specified and generated target name already exists, number is added to the target's name suffix if --force is not enabled. For example, if the source is "file.pdf" and the target is not specified, the target will be "file_signed.pdf". If the target already exists, the target will be "file_signed (1).pdf". If that target already exists, the target will be "file_signed (2).pdf", and so on.

                If --force is enabled, the target will be overwritten if it already exists.

                If target is specified with missing parent directories, they are created onyl if --parents is enabled. Otherwise, the signing fails. For example, if the source is "file.pdf" and the target is "target/file_signed.pdf", the target directory "target" must exist. If it does not exist, the signing fails. If --parents is enabled, the target directory "target" is created if it does not exist.
                """;

        formatter.printHelp(80, syntax, "", options, footer, true);
    }

    public static void printUsage() {
        final HelpFormatter formatter = new HelpFormatter();
        final String syntax = """
                autogram [options]
                autogram --url=http://localhost:32700
                autogram --cli [options]
                autogram --cli -s target/directory-example/file-example.pdf -t target/output-example/out-example.pdf
                autogram --cli -s target/directory-example -t target/output-example -f
                autogram --cli -s target/directory-example -t target/non-existent-dir/output-example --parents
                autogram --cli -s target/directory-example/file-example.pdf -pdfa
                autogram --cli -s target/directory-example/file-example.pdf -d eid
                autogram --cli -s target/file-example.pdf -d eid --tsa-server http://timestamp.sectigo.com/qualified
                autogram --cli -s target/file-example.pdf -d eid --tsa-server "http://tsa.belgium.be/connect,http://timestamp.sectigo.com/qualified"
                """;
        final PrintWriter pw = new PrintWriter(System.out);
        formatter.printUsage(pw, 80, syntax);
        pw.flush();
    }
}
