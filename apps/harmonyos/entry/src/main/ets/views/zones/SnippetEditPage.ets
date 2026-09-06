import { HdsNavDestination } from '@kit.UIDesignKit';
// Snippet 编辑：新建（命名 + 代码）或改正文，multipart 上传（对齐 Android SnippetEdit 屏）。
import { SnippetEditParam } from '../../models/Routes';
import { SnippetService } from '../../services/SnippetService';
import { BRAND_ORANGE, OCLoading } from '../common/Components';
import { OCSkyBackground } from '../common/OCSky';

const TEMPLATE = `export default {
  async fetch(request) {
    // 在边缘改写请求/响应
    return fetch(request);
  }
};
`;

@ComponentV2
export struct SnippetEditPage {
  @Local zoneId: string = '';
  @Local zoneName: string = '';
  @Local snippetName: string = '';
  @Local isNew: boolean = true;
  @Local code: string = TEMPLATE;
  @Local isLoading: boolean = false;
  @Local isSaving: boolean = false;
  @Local error: string = '';
  private service: SnippetService = new SnippetService();
  private pathStack: NavPathStack | null = null;

  private save(): void {
    const name = this.snippetName.trim();
    if (name === '') {
      return;
    }
    this.isSaving = true;
    this.error = '';
    this.service.upload(this.zoneId, name, this.code).then(() => {
      this.isSaving = false;
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      this.pathStack?.pop();
    }).catch((e: Error) => {
      this.isSaving = false;
      this.error = e.message ?? '保存失败';
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        OCSkyBackground()
        if (this.isLoading) {
          Column() {
            OCLoading({ text: '正在加载正文…' })
          }
          .width('100%')
          .height('100%')
        } else {
          Column({ space: 12 }) {
            if (this.isNew) {
              TextInput({ text: this.snippetName, placeholder: '片段名（小写字母/数字/下划线）' })
                .fontSize(14)
                .width('100%')
                .onChange((value: string) => {
                  this.snippetName = value;
                })
            }

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

            Button(this.isSaving ? '正在上传…' : '保存并部署')
              .width('100%')
              .height(46)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.oc_brand_cta'))
              .enabled(!this.isSaving && this.snippetName.trim() !== '' && this.code.trim() !== '')
              .onClick(() => {
                this.save();
              })
          }
          .padding(16)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: this.isNew ? '新建 Snippet' : this.snippetName } } })
    .backgroundColor($r('sys.color.background_secondary'))
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as SnippetEditParam;
      this.zoneId = param.zoneId;
      this.zoneName = param.zoneName;
      this.snippetName = param.snippetName;
      this.isNew = param.snippetName === '';
      if (!this.isNew) {
        this.isLoading = true;
        this.service.content(param.zoneId, param.snippetName).then((code: string) => {
          this.code = code;
          this.isLoading = false;
        }).catch((e: Error) => {
          this.error = e.message ?? '加载正文失败';
          this.isLoading = false;
        });
      }
    })
  }
}
