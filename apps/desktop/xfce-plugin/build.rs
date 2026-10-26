//! Compiles the C shim that registers the plugin with the XFCE panel, and links
//! libxfce4panel.

fn main() {
    println!("cargo:rerun-if-changed=src/shim.c");
    let panel = match pkg_config::Config::new()
        .atleast_version("4.12")
        .probe("libxfce4panel-2.0")
    {
        Ok(library) => library,
        Err(error) => {
            println!(
                "cargo:warning=libxfce4panel-2.0 not found ({error}); install libxfce4panel-2.0-dev"
            );
            std::process::exit(1);
        }
    };
    let mut build = cc::Build::new();
    build.file("src/shim.c");
    for path in &panel.include_paths {
        build.include(path);
    }
    build.compile("salatwidget_xfce_shim");
}
