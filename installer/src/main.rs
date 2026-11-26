//! The installer of the distribution, installed as `<id>-install`.
//!
//! ```text
//! <id>-install --core --answers FILE [--secrets FILE] [--hardware-nix FILE] [--no-unmount]
//!                                  install without asking (as root): the graphical installer
//!                                  and the automated test
//! <id>-install --facts             the computer as JSON (memory, disks and, as root, their
//!                                  partitions, Secure Boot)
//! <id>-install --serve             the back end of the graphical installer on $SOCKET
//! <id>-install --version
//! ```
//!
//! Without --secrets the password is read from /run/<id>-install/user.pass and, with
//! encryption, the passphrase from /tmp/<id>-luks.key. The answers file holds no secrets.

mod checks;
mod core;
mod facts;
mod layout;
mod serve;

use std::path::PathBuf;
use std::process::ExitCode;

fn usage(id: &str) -> String {
    format!(
        "Usage: {id}-install --core --answers FILE [--secrets FILE] [--hardware-nix FILE] [--no-unmount]
       {id}-install --facts | --serve | --version

The installer of the live session is the window that opens by itself; open it again from
the desktop or with Search (\"Install\"). This command is what it runs underneath.

  --core --answers FILE   Install from an answers file without asking (as root).
  --secrets FILE          The password and the passphrase as JSON; deleted after reading.
  --hardware-nix FILE     Use this hardware.nix instead of detecting one (tests).
  --no-unmount            Leave /mnt mounted at the end (tests).
  --facts                 What a front end needs to know about this computer, as JSON.
  --serve                 The back end of the graphical installer, on $SOCKET.
"
    )
}

fn main() -> ExitCode {
    let env = core::Env::from_environment();
    let mut args = std::env::args().skip(1);
    let mut mode = "";
    let mut answers = None;
    let mut secrets = None;
    let mut hardware_nix = None;
    let mut unmount = true;
    while let Some(arg) = args.next() {
        let mut value = |name: &str| {
            args.next()
                .map(PathBuf::from)
                .ok_or(format!("{name} needs a file"))
        };
        let step = match arg.as_str() {
            "--core" => {
                mode = "core";
                Ok(())
            }
            "--facts" => {
                mode = "facts";
                Ok(())
            }
            "--serve" => {
                mode = "serve";
                Ok(())
            }
            "--version" => {
                println!("{} {}", env.name, env.version);
                return ExitCode::SUCCESS;
            }
            "-h" | "--help" => {
                print!("{}", usage(&env.id));
                return ExitCode::SUCCESS;
            }
            "--answers" => value("--answers").map(|f| answers = Some(f)),
            "--secrets" => value("--secrets").map(|f| secrets = Some(f)),
            "--hardware-nix" => value("--hardware-nix").map(|f| hardware_nix = Some(f)),
            "--no-unmount" => {
                unmount = false;
                Ok(())
            }
            _ => Err(format!("unknown option {arg}")),
        };
        if let Err(e) = step {
            eprintln!("{e}\n\n{}", usage(&env.id));
            return ExitCode::from(64);
        }
    }

    match mode {
        "facts" => {
            println!("{}", facts::facts(&env.name, &env.id, &env.version));
            ExitCode::SUCCESS
        }
        "serve" => {
            let var = |k: &str, d: &str| std::env::var(k).unwrap_or_else(|_| d.to_string());
            let Ok(socket) = std::env::var("SOCKET") else {
                eprintln!("--serve needs SOCKET");
                return ExitCode::from(64);
            };
            let install_command =
                std::env::current_exe().unwrap_or_else(|_| format!("{}-install", env.id).into());
            let cfg = serve::Config {
                socket: socket.into(),
                install_command: var("INSTALL_COMMAND", &install_command.to_string_lossy()).into(),
                sudo: var("SUDO", "/run/wrappers/bin/sudo").into(),
                nmcli: var("NMCLI", "nmcli"),
                name: env.name.clone(),
                id: env.id.clone(),
                version: env.version.clone(),
            };
            match serve::serve(cfg) {
                Ok(()) => ExitCode::SUCCESS,
                Err(e) => {
                    eprintln!("{e}");
                    ExitCode::FAILURE
                }
            }
        }
        "core" => {
            let Some(answers) = answers else {
                eprintln!("--core needs --answers FILE");
                return ExitCode::from(64);
            };
            let opts = core::Options {
                answers,
                secrets,
                hardware_nix,
                unmount,
            };
            match core::install(&env, &opts) {
                Ok(()) => ExitCode::SUCCESS,
                Err(e) => {
                    println!("Error: {e}");
                    println!(
                        "Installation failed. The full log is in {}",
                        env.log_file().display()
                    );
                    ExitCode::FAILURE
                }
            }
        }
        _ => {
            print!("{}", usage(&env.id));
            ExitCode::from(64)
        }
    }
}
