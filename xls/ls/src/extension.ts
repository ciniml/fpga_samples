import * as vscode from 'vscode';
import * as vscodelc from 'vscode-languageclient/node';

// Global object to dispose of previous language clients.
let client: undefined | vscodelc.LanguageClient = undefined;

async function initLanguageClient() {
    const output = vscode.window.createOutputChannel('DSLX Language Server');
    const config = vscode.workspace.getConfiguration('dslx');
    const binary_path = config.get('path') as string

    const dslx_ls: vscodelc.Executable = {
        command: binary_path,
        args: await config.get<string[]>('arguments')
    };

    const serverOptions: vscodelc.ServerOptions = dslx_ls;

    // Options to control the language client
    const clientOptions: vscodelc.LanguageClientOptions = {
        // Register the server for DSLX documents
        documentSelector: [{ scheme: 'file', language: 'dslx' }],
        outputChannel: output
    };

    // Create the language client and start the client.
    client = new vscodelc.LanguageClient(
        'dslx',
        'DSLX Language Server',
        serverOptions,
        clientOptions
    );
    client.start();
}

// VSCode entrypoint to bootstrap an extension
export function activate(_: vscode.ExtensionContext) {
    // If a configuration change even it fired, let's dispose
    // of the previous client and create a new one.
    vscode.workspace.onDidChangeConfiguration(async (event) => {
        if (!event.affectsConfiguration('dslx')) {
            return;
        }
        if (!client) {
            return initLanguageClient();
        }
        client.stop().finally(() => {
            initLanguageClient();
        });
    });
    return initLanguageClient();
}

// Entrypoint to tear it down.
export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
