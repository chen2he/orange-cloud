// 新建 Worker：命名 + 代码编辑器（默认 Hello World），multipart 部署（对齐 Android WorkerCreateScreen）。
import { WorkerService } from '../../services/WorkerService';
import { accountStore } from '../../core/store/AccountStore';
import { BRAND_ORANGE } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

interface WorkerTemplate {
  label: string;
  code: string;
}

const TEMPLATES: WorkerTemplate[] = [
  {
    label: 'Hello World',
    code: `export default {
  async fetch(request, env, ctx) {
    return new Response("Hello from Orange Cloud!");
  }
};
`,
  },
  {
    label: 'JSON API',
    code: `export default {
  async fetch(request, env, ctx) {
    return Response.json({ ok: true, path: new URL(request.url).pathname });
  }
};
`,
  },
  {
    label: '重定向',
    code: `export default {
  async fetch(request, env, ctx) {
    return Response.redirect("https://example.com", 302);
  }
};
`,
  },
];

/// CF 脚本名规则：小写字母/数字/连字符/下划线，且不以连字符开头结尾。
function isValidName(name: string): boolean {
  return /^[a-z0-9][a-z0-9_-]*$/.test(name) && !name.endsWith('-');
}

function today(): string {
  const now = new Date();
  const m = now.getMonth() + 1;
  const d = now.getDate();
  return `${now.getFullYear()}-${m < 10 ? '0' : ''}${m}-${d < 10 ? '0' : ''}${d}`;
}

@ComponentV2
export struct WorkerCreatePage {
  @Local name: string = '';
  @Local code: string = TEMPLATES[0].code;
  @Local templateIdx: number = 0;
  @Local compatDate: string = today();
  @Local isSaving: boolean = false;
  @Local error: string = '';
  private service: WorkerService = new WorkerService();
  private pathStack: NavPathStack | null = null;

  private nameValid(): boolean {
    const n = this.name.trim();
    return n !== '' && isValidName(n);
  }

  private deploy(): void {
    this.isSaving = true;
    this.error = '';
    this.service.deploy(accountStore.selectedId, this.name.trim(), this.code, this.compatDate.trim()).then(() => {
      this.isSaving = false;
      this.getUIContext().getPromptAction().showToast({ message: '已部署' });
      this.pathStack?.pop();
    }).catch((e: Error) => {
      this.isSaving = false;
      this.error = e.message ?? '部署失败';
    });
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        Column({ space: 12 }) {
          TextInput({ text: this.name, placeholder: '脚本名（小写字母/数字/连字符）' })
            .fontSize(14)
            .width('100%')
            .onChange((value: string) => {
              this.name = value;
            })
          if (this.name.trim() !== '' && !this.nameValid()) {
            Text('名称仅能含小写字母、数字、- 和 _，且不能以 - 结尾')
              .fontSize(12)
              .fontColor('#DC2626')
              .width('100%')
          }

          Row({ space: 12 }) {
            Text('起始模板')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Select(TEMPLATES.map((t: WorkerTemplate): SelectOption => ({ value: t.label })))
              .selected(this.templateIdx)
              .value(TEMPLATES[this.templateIdx].label)
              .font({ size: 14 })
              .onSelect((index: number) => {
                this.templateIdx = index;
                this.code = TEMPLATES[index].code;
              })
          }
          .width('100%')

          Row({ space: 12 }) {
            Text('兼容性日期')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            TextInput({ text: this.compatDate, placeholder: 'YYYY-MM-DD' })
              .fontSize(14)
              .fontFamily('monospace')
              .width(140)
              .onChange((value: string) => {
                this.compatDate = value;
              })
          }
          .width('100%')

          TextArea({ text: this.code })
            .fontSize(12)
            .fontFamily('monospace')
            .width('100%')
            .layoutWeight(1)
            .onChange((value: string) => {
              this.code = value;
            })

          if (this.error !== '') {
            Text(this.error)
              .fontSize(13)
              .fontColor('#DC2626')
              .width('100%')
          }

          Button(this.isSaving ? '正在部署…' : '部署')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor(BRAND_ORANGE)
            .enabled(!this.isSaving && this.nameValid() && this.code.trim() !== '')
            .onClick(() => {
              this.deploy();
            })
        }
        .padding(16)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .title('新建 Worker')
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
