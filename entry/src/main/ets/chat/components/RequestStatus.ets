import { RequestPhase } from '../state/ChatState';

@ComponentV2
export struct RequestStatus {
  @Param phase: RequestPhase = 'loading';
  @Param unconfirmed: boolean = false;
  @Param canRetry: boolean = false;
  @Param canRetryLoad: boolean = false;
  @Param notice: string = '';
  @Event onRetry: () => void = () => {};

  private label(): Resource {
    if (this.unconfirmed && this.phase !== 'sending' && this.phase !== 'stopping') {
      return $r('app.string.chat_checking');
    }
    if (this.phase === 'loading') {
      return $r('app.string.chat_loading');
    }
    if (this.phase === 'sending') {
      return $r('app.string.chat_sending');
    }
    if (this.phase === 'processing') {
      return $r('app.string.chat_processing');
    }
    if (this.phase === 'stopping') {
      return $r('app.string.chat_stopping');
    }
    if (this.phase === 'checking') {
      return $r('app.string.chat_checking');
    }
    if (this.canRetryLoad) {
      return $r('app.string.chat_load_failed');
    }
    return $r('app.string.chat_failed');
  }

  build() {
    Column({ space: 4 }) {
      if (this.phase !== 'ready' || this.canRetry) {
        Row({ space: 8 }) {
          Text(this.label()).fontSize(13).lineHeight(20)
            .fontColor($r('app.color.chat_secondary')).layoutWeight(1)
          if (this.canRetry) {
            Button($r('app.string.chat_retry')).id('chat-retry').height(44)
              .fontSize(13).backgroundColor(Color.Transparent)
              .fontColor($r('app.color.chat_accent'))
              .onClick(() => this.onRetry())
          }
        }
      }
      if (this.notice.length > 0) {
        Text(this.notice).fontSize(13).lineHeight(20)
          .fontColor($r('app.color.chat_secondary')).width('100%')
      }
    }.padding({ left: 22, right: 22 })
  }
}
