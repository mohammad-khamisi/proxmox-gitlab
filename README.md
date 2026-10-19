# proxmox-gitlab

با Terraform (یا OpenTofu) دو ماشین مجازی روی Proxmox می‌سازد:

| VM | کار |
|----|-----|
| `gitlab` | سرور GitLab CE (Omnibus) روی Ubuntu 24.04 |
| `gitlab-runner` | GitLab Runner با executor نوع Docker که **خودکار** به همین GitLab وصل (register) می‌شود |

همه چیز با cloud-init انجام می‌شود و کار دستی لازم نیست؛ بعد از `terraform apply` حدود ۱۰ تا ۲۰ دقیقه طول می‌کشد تا GitLab بالا بیاید و Runner خودش ثبت شود.

## روند کار

1. ایمیج cloud ابونتو 24.04 روی نود Proxmox دانلود می‌شود.
2. فایل user-data هر VM به‌صورت snippet روی Proxmox آپلود می‌شود.
3. **VM گیت‌لب:** GitLab نصب می‌شود، رمز اولیه‌ی `root` تنظیم می‌شود و یک Personal Access Token با scope `create_runner` ساخته می‌شود (مقدار توکن را Terraform تولید می‌کند). ثبت‌نام عمومی (sign-up) هم غیرفعال می‌شود.
4. **VM رانر:** Docker و `gitlab-runner` نصب می‌شوند، صبر می‌کند تا GitLab آماده شود، با API یک instance runner می‌سازد (`POST /api/v4/user/runners`) و با توکن `glrt-...` دستور `gitlab-runner register` را اجرا می‌کند.
5. بعد از ثبت، توکن‌ها و رمزها از روی دیسک هر دو VM پاک می‌شوند.

## پیش‌نیازها

- Terraform نسخه‌ی 1.5 به بالا یا OpenTofu
- Proxmox VE نسخه‌ی 8 یا بالاتر
- دسترسی SSH به نود Proxmox (provider فایل‌های snippet را از طریق SSH آپلود می‌کند)
- دو IP ثابت آزاد در شبکه‌ی شما

### ۱. فعال کردن snippets روی datastore

روی نود Proxmox اجرا کنید:

```bash
pvesm set local --content iso,vztmpl,backup,snippets
```

### ۲. ساخت کاربر و API Token برای Terraform

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
# مقادیر terraform.tfvars را ویرایش کنید (آدرس Proxmox، توکن، IPها، کلید SSH)

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

با کاربر `root` و این رمز وارد GitLab شوید. در مسیر **Admin → CI/CD → Runners** باید رانر `gitlab-runner` را با وضعیت سبز (online) ببینید.

## تست رانر

فایل [`examples/.gitlab-ci.yml`](examples/.gitlab-ci.yml) را در یک پروژه‌ی جدید روی GitLab خودتان push کنید؛ pipeline باید روی رانر جدید اجرا شود.

## عیب‌یابی

```bash
# روی VM گیت‌لب
ssh ubuntu@<gitlab-ip>
sudo tail -f /var/log/install-gitlab.log
sudo gitlab-ctl status

# روی VM رانر
ssh ubuntu@<runner-ip>
sudo tail -f /var/log/install-runner.log
sudo gitlab-runner verify
sudo cat /var/log/cloud-init-output.log
```

## متغیرهای مهم

| متغیر | پیش‌فرض | توضیح |
|-------|---------|-------|
| `proxmox_node` | `pve` | نام نود |
| `vm_datastore` | `local-lvm` | محل دیسک VMها |
| `snippets_datastore` | `local` | datastore با قابلیت snippets |
| `network_bridge` | `vmbr0` | bridge شبکه |
| `vlan_id` | `null` | تگ VLAN (اختیاری) |
| `gitlab_vm` | - | `vm_id`، `name`، `ip` (CIDR)، `cores`=4، `memory_mb`=8192، `disk_gb`=50 |
| `runner_vm` | - | `vm_id`، `name`، `ip` (CIDR)، `cores`=2، `memory_mb`=4096، `disk_gb`=40 |
| `gitlab_external_url` | `http://<gitlab ip>` | آدرس GitLab (مثلاً با دامنه) |
| `gitlab_edition` | `gitlab-ce` | `gitlab-ce` یا `gitlab-ee` |
| `runner_tags` | `["docker","proxmox"]` | تگ‌های رانر |
| `runner_concurrent` | `2` | تعداد jobهای هم‌زمان |
| `runner_docker_privileged` | `false` | برای docker-in-docker برابر `true` بگذارید |

> GitLab حداقل ۴ گیگابایت رم لازم دارد؛ ۸ گیگابایت توصیه می‌شود.

## ساختار پروژه

```
.
├── versions.tf               # providerها (bpg/proxmox, random)
├── variables.tf
├── main.tf                   # ایمیج، snippetها و دو VM
├── outputs.tf
├── modules/vm/               # ماژول ساخت VM روی Proxmox
├── cloud-init/
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
