import { Container } from "theme-ui";

import { Trove } from "../components/Trove/Trove";
import { Stability } from "../components/Stability/Stability";
import { RedemptionManager } from "../components/RedemptionManager";
import { SystemStats } from "../components/SystemStats";
import { PriceManager } from "../components/PriceManager";
import { LiquidationManager } from "../components/LiquidationManager";
import { RiskiestTroves } from "../components/RiskiestTroves";
import { TroveViewProvider } from "../components/Trove/context/TroveViewProvider";
import { StabilityViewProvider } from "../components/Stability/context/StabilityViewProvider";
import { StakingViewProvider } from "../components/Staking/context/StakingViewProvider";
import { Staking } from "../components/Staking/Staking";
import { MineViewProvider } from "../components/Mine/context/MineViewProvider";
import { Mine } from "../components/Mine/Mine";

export const Dashboard: React.FC = () => (
  <>
    <Container variant="columns">
      <Container variant="left">
        <TroveViewProvider>
          <Trove />
        </TroveViewProvider>

        <StabilityViewProvider>
          <Stability />
        </StabilityViewProvider>

        <StakingViewProvider>
          <Staking />
        </StakingViewProvider>

        <RedemptionManager />

        <MineViewProvider>
          <Mine />
        </MineViewProvider>
      </Container>

      <Container variant="right">
        <SystemStats />
        <PriceManager />
        <LiquidationManager />
      </Container>
    </Container>

    <RiskiestTroves pageSize={10} />
  </>
);
