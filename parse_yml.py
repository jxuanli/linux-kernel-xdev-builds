import yaml, os

f = open(os.environ["CONFIG_FILE"])
config = yaml.safe_load(f)
f = open(os.environ["GITHUB_OUTPUT"], "w")
f.write(f"version={config['version']}\n")
f.write(f"ktype={config['type']}\n")
frag = "frags/" + ".".join(os.environ["CONFIG_FILE"].split("/")[-1].split(".")[:-1]) + ".config"
f.write(f"frag={frag}\n")
f = open(frag, "w+")
kernel_configs = config["configs"]
for config, val in kernel_configs.items():
    f.write(f"{config}={val}\n")
