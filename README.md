# proxmox-gitlab

با Terraform (یا OpenTofu) روی Proxmox یک سرور GitLab CE به‌همراه GitLab Runner (با executor داکر) بالا می‌آورد. Runner **خودکار** به همین GitLab وصل (register) می‌شود. سیستم‌عامل Ubuntu 24.04 است.

دو حالت استقرار دارد (متغیر `deployment_mode`):

| حالت | توضیح |
|------|-------|
| `single` (پیش‌فرض) | GitLab و Runner هر دو روی **یک VM** |
| `separate` | یک VM برای GitLab و یک VM جدا برای Runner |

همه چیز با cloud-init انجام می‌شود و کار دستی لازم نیست؛ بعد از `terraform apply` حدود ۱۰ تا ۲۰ دقیقه طول می‌کشد تا GitLab بالا بیاید و Runner خودش ثبت شود.

## روند کار

1. ایمیج cloud ابونتو 24.04 روی نود Proxmox دانلود می‌شود.
2. فایل user-data هر VM به‌صورت snippet روی Proxmox آپلود می‌شود.
3. **GitLab:** GitLab نصب می‌شود، رمز اولیه‌ی `root` تنظیم می‌شود و یک Personal Access Token با scope `create_runner` ساخته می‌شود (مقدار توکن را Terraform تولید می‌کند). ثبت‌نام عمومی (sign-up) هم غیرفعال می‌شود.
4. **Runner** (در حالت `single` روی همان VM و بعد از نصب GitLab): Docker و `gitlab-runner` نصب می‌شوند، صبر می‌کند تا GitLab آماده شود، با API یک instance runner می‌سازد (`POST /api/v4/user/runners`) و با توکن `glrt-...` دستور `gitlab-runner register` را اجرا می‌کند.
5. بعد از ثبت، توکن‌ها و رمزها از روی دیسک پاک می‌شوند.

> در حالت `single` آدرس GitLab برای Runner همان IP خود VM است (نه `localhost`)، چون کانتینرهای job برای `git clone` باید به GitLab دسترسی داشته باشند.

## پیش‌نیازها

- Terraform نسخه‌ی 1.5 به بالا یا OpenTofu
- Proxmox VE نسخه‌ی 8 یا بالاتر
- دسترسی SSH به نود Proxmox (provider فایل‌های snippet را از طریق SSH آپلود می‌کند)
- یک IP ثابت آزاد (در حالت `separate` دو IP)

### ۱. استوریج‌ها

- **دیسک VM:** پیش‌فرض روی `iscsi-netapp` ساخته می‌شود (`vm_datastore`).
  این استوریج باید از نوع **LVM روی iSCSI** (یا هر نوعی با محتوای `images`) باشد. استوریج خام از نوع `iscsi` فقط LUN را نشان می‌دهد و نمی‌توان روی آن دیسک ساخت. نوع و محتوای آن را با این دستور ببینید:

  ```bash
  pvesm status
  grep -A6 'iscsi-netapp' /etc/pve/storage.cfg
  ```

  اگر نوعش `iscsi` است (نه `lvm`)، یک LVM روی آن LUN بسازید و در `vm_datastore` نام همان LVM را بگذارید.
- **ایمیج و snippetها:** iSCSI/LVM از فایل پشتیبانی نمی‌کند، پس ایمیج cloud و فایل‌های cloud-init روی یک استوریج فایلی مثل `local` می‌مانند (`image_datastore`، `snippets_datastore`).

### ۲. فعال کردن snippets روی datastore

روی نود Proxmox اجرا کنید:

```bash
pvesm set local --content iso,vztmpl,backup,snippets
```

### ۳. ساخت کاربر و API Token برای Terraform

```bash
pveum role add TerraformProv -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role TerraformProv
pveum user token add terraform@pve provider --privsep=0
```

خروجی دستور آخر را به شکل `terraform@pve!provider=<uuid>` در `proxmox_api_token` قرار دهید.

> نکته: اگر نسخه‌ی Proxmox شما privilege مربوط به `SDN.Use` یا `VM.Monitor` را نمی‌شناسد، آن را از لیست حذف یا اضافه کنید.

## نصب و اجرا

```bash
git clone https://github.com/mohammad-khamisi/proxmox-gitlab.git
cd proxmox-gitlab

cp terraform.tfvars.example terraform.tfvars
# مقادیر terraform.tfvars را ویرایش کنید (آدرس Proxmox، توکن، IP، کلید SSH)

eval "$(ssh-agent)" && ssh-add ~/.ssh/id_ed25519   # برای SSH به نود Proxmox

terraform init
terraform plan
terraform apply
```

بعد از اتمام:

```bash
terraform output gitlab_url
terraform output -raw gitlab_root_password    # رمز کاربر root در GitLab
```

با کاربر `root` و این رمز وارد GitLab شوید. در مسیر **Admin → CI/CD → Runners** باید رانر (در حالت `single` با نام همان VM، مثلاً `gitlab`) را با وضعیت سبز (online) ببینید.

## تست رانر

فایل [`examples/.gitlab-ci.yml`](examples/.gitlab-ci.yml) را در یک پروژه‌ی جدید روی GitLab خودتان push کنید؛ pipeline باید روی رانر جدید اجرا شود.

## عیب‌یابی

```bash
# GitLab (در حالت single هر دو روی همین VM)
ssh ubuntu@<gitlab-ip>
sudo tail -f /var/log/install-gitlab.log
sudo gitlab-ctl status

# Runner (در حالت separate روی VM رانر)
sudo tail -f /var/log/install-runner.log
sudo gitlab-runner verify
sudo cat /var/log/cloud-init-output.log
```

## متغیرهای مهم

| متغیر | پیش‌فرض | توضیح |
|-------|---------|-------|
| `deployment_mode` | `single` | `single` یا `separate` |
| `proxmox_node` | `pve` | نام نود |
| `vm_datastore` | `iscsi-netapp` | محل دیسک VMها |
| `image_datastore` | `local` | محل ایمیج cloud ابونتو |
| `ubuntu_image_file_id` | `""` | اگر ایمیج را خودتان آپلود کرده‌اید، مثلاً `iso:iso/noble-server-cloudimg-amd64.img`؛ در این حالت چیزی دانلود نمی‌شود |
| `snippets_datastore` | `local` | datastore با قابلیت snippets |
| `network_bridge` | `vmbr0` | bridge شبکه |
| `vlan_id` | `null` | تگ VLAN (اختیاری) |
| `gitlab_vm` | - | `vm_id`، `name`، `ip` (CIDR)، `cores`، `memory_mb`، `disk_gb` — پیش‌فرض منابع: در `single` برابر 6 هسته / 12GB / 80GB و در `separate` برابر 4 / 8GB / 50GB |
| `runner_vm` | `null` | فقط در `separate`: `vm_id`، `name`، `ip`، `cores`=2، `memory_mb`=4096، `disk_gb`=40 |
| `gitlab_external_url` | `http://<gitlab ip>` | آدرس GitLab (مثلاً با دامنه) |
| `gitlab_edition` | `gitlab-ce` | `gitlab-ce` یا `gitlab-ee` |
| `runner_tags` | `["docker","proxmox"]` | تگ‌های رانر |
| `runner_concurrent` | `2` | تعداد jobهای هم‌زمان |
| `runner_docker_privileged` | `false` | برای docker-in-docker برابر `true` بگذارید |

> GitLab به‌تنهایی حداقل ۴ گیگابایت رم لازم دارد. در حالت `single` jobهای CI هم روی همان VM اجرا می‌شوند، برای همین منابع بیشتری در نظر گرفته شده است.
>
> **امنیت:** در حالت `single` jobها روی همان سرور GitLab اجرا می‌شوند. اگر `runner_docker_privileged = true` باشد، هر job عملاً به کل سرور دسترسی دارد. برای محیط production حالت `separate` بهتر است.

## ساختار پروژه

```
.
├── versions.tf               # providerها (bpg/proxmox, random)
├── variables.tf
├── main.tf                   # ایمیج، snippetها و VMها
├── outputs.tf
├── modules/vm/               # ماژول ساخت VM روی Proxmox
├── cloud-init/
│   ├── all-in-one.yaml.tftpl # حالت single
│   ├── gitlab.yaml.tftpl
│   └── runner.yaml.tftpl
├── scripts/
│   ├── install-gitlab.sh
│   ├── gitlab-bootstrap.rb   # ساخت توکن ثبت رانر داخل GitLab
│   └── install-runner.sh
├── examples/.gitlab-ci.yml
└── terraform.tfvars.example
```

## حذف

```bash
terraform destroy
```
