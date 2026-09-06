// 当前身份下的 Cloudflare 账户（account）列表与选中项（对齐 Android AccountStore）。
// 一个身份可访问多个账户；选中账户按身份持久化到 Preferences。
import { Account } from '../../models/Models';
import { AccountService } from '../../services/AccountService';
import { authManager } from '../auth/AuthManager';
import { AppPrefs } from '../system/AppPrefs';

@ObservedV2
export class AccountStore {
  @Trace accounts: Account[] = [];
  @Trace selectedId: string = '';
  @Trace selectedName: string = '';
  @Trace isLoading: boolean = false;
  @Trace error: string = '';

  private service: AccountService = new AccountService();
  private loadedForSession: string = '';

  /// 身份切换后调用；同身份重复调用为幂等
  async loadIfNeeded(): Promise<void> {
    const sessionId = authManager.currentSessionId;
    if (sessionId === '' || (this.loadedForSession === sessionId && this.accounts.length > 0)) {
      return;
    }
    await this.reload();
  }

  async reload(): Promise<void> {
    const sessionId = authManager.currentSessionId;
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.error = '';
    try {
      const accounts = await this.service.fetchAccounts();
      this.accounts = accounts;
      this.loadedForSession = sessionId;
      if (accounts.length === 0) {
        this.selectedId = '';
        this.selectedName = '';
        this.error = '该身份下没有可访问的 Cloudflare 账户';
        return;
      }
      const saved = await AppPrefs.getString(`selected_account_${sessionId}`, '');
      const match = accounts.find((a: Account) => a.id === saved);
      const chosen = match ?? accounts[0];
      this.selectedId = chosen.id;
      this.selectedName = chosen.name;
    } catch (e) {
      this.error = (e as Error).message ?? '加载账户失败';
    } finally {
      this.isLoading = false;
    }
  }

  async select(account: Account): Promise<void> {
    this.selectedId = account.id;
    this.selectedName = account.name;
    await AppPrefs.putString(`selected_account_${authManager.currentSessionId}`, account.id);
  }
}

/// 全局单例（随身份切换 reload）
export const accountStore = new AccountStore();
